import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct PopoverFeature {
    @ObservableState
    struct State: Equatable {
        var availableUpdate: String?
        var currentVersion: String?
        var error: String?
        var isLoading = false
        var lastUpdated: Date?
        var needsLogin = false
        var profile: ClaudeProfile?
        var session: UsageWindow?
        var showCopiedConfirmation = false
        @Shared(.appStorage("showPercentageInMenuBar")) var showPercentage = false
        @Shared(.appStorage("showRemainingInsteadOfUsed")) var showRemaining = false
        var launchAtLogin = true
        var weekly: UsageWindow?
        var weeklyPace: PaceReserve?
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case bundleVersionCheckTicked
        case copiedConfirmationDismissed
        case launchAtLoginLoaded(Bool)
        case launchAtLoginToggled(Bool)
        case onAppLaunch
        case onAppear
        case profileResponse(Result<ClaudeProfile, any Error>)
        case quitButtonTapped
        case refreshButtonTapped
        case retryButtonTapped
        case timerTicked
        case updateBannerTapped
        case usageResponse(Result<ClaudeUsage, any Error>)
        case versionCheckResponse(Result<GitHubRelease, any Error>)
    }

    enum CancelID {
        case bundleMonitor
        case copiedConfirmation
        case timer
    }

    /// Minimum time between automatic fetches triggered by opening the popover.
    private static let cacheInterval: TimeInterval = 60

    @Dependency(ClaudeAPIClient.self) var apiClient
    @Dependency(AppTerminator.self) var appTerminator
    @Dependency(\.continuousClock) var clock
    @Dependency(LaunchAtLoginClient.self) var launchAtLoginClient
    @Dependency(\.date.now) var now
    @Dependency(VersionClient.self) var versionClient

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .bundleVersionCheckTicked:
                if let currentVersion = state.currentVersion,
                   let diskVersion = versionClient.onDiskVersion(),
                   diskVersion != currentVersion {
                    return .run { _ in appTerminator.relaunch() }
                }
                return .none

            case .copiedConfirmationDismissed:
                state.showCopiedConfirmation = false
                return .none

            case .launchAtLoginLoaded(let isEnabled):
                state.launchAtLogin = isEnabled
                return .none

            case .launchAtLoginToggled(let isEnabled):
                state.launchAtLogin = isEnabled
                return .run { send in
                    try? launchAtLoginClient.setEnabled(isEnabled)
                    let actualState = launchAtLoginClient.isEnabled()
                    await send(.launchAtLoginLoaded(actualState))
                }

            case .onAppLaunch:
                state.currentVersion = versionClient.currentVersion()
                return .merge(
                    refreshAndRestartTimer(state: &state),
                    .run { send in
                        for await _ in clock.timer(interval: .seconds(15)) {
                            await send(.bundleVersionCheckTicked)
                        }
                    }
                    .cancellable(id: CancelID.bundleMonitor, cancelInFlight: true),
                    .run { send in
                        @Shared(.appStorage("hasSetUpLaunchAtLogin")) var hasSetUp = false
                        if !hasSetUp {
                            $hasSetUp.withLock { $0 = true }
                            if !launchAtLoginClient.isEnabled() {
                                try? launchAtLoginClient.setEnabled(true)
                            }
                        }
                        let isEnabled = launchAtLoginClient.isEnabled()
                        await send(.launchAtLoginLoaded(isEnabled))
                    }
                )

            case .onAppear:
                // The popover's onAppear fires on every menu-bar click. Avoid hammering
                // the rate-limited usage endpoint: reuse cached data if we refreshed within
                // the last minute. The 15-minute timer and the manual Refresh button are
                // unaffected and always fetch.
                if let lastUpdated = state.lastUpdated,
                   now.timeIntervalSince(lastUpdated) < Self.cacheInterval {
                    return .none
                }
                return refreshAndRestartTimer(state: &state)

            case .profileResponse(.success(let profile)):
                state.profile = profile
                return .none

            case .profileResponse(.failure):
                return .none

            case .quitButtonTapped:
                return .run { _ in appTerminator.terminate() }

            case .refreshButtonTapped:
                return fetchUsage(state: &state)

            case .retryButtonTapped:
                return fetchUsage(state: &state)

            case .timerTicked:
                return .merge(
                    fetchUsage(state: &state),
                    checkForUpdates()
                )

            case .updateBannerTapped:
                versionClient.copyUpdateCommand()
                state.showCopiedConfirmation = true
                return .run { send in
                    try await clock.sleep(for: .seconds(2))
                    await send(.copiedConfirmationDismissed)
                }
                .cancellable(id: CancelID.copiedConfirmation, cancelInFlight: true)

            case .usageResponse(.success(let usage)):
                state.isLoading = false
                state.session = usage.session
                state.weekly = usage.weekly
                state.weeklyPace = usage.weekly.paceReserve(now: now)
                state.lastUpdated = now
                state.error = nil
                state.needsLogin = false
                return .none

            case .usageResponse(.failure(let error)):
                state.isLoading = false
                if let claudeError = error as? ClaudeError, claudeError.isAuthError {
                    state.error = claudeError.localizedDescription
                    state.needsLogin = true
                } else {
                    state.error = error.localizedDescription
                    state.needsLogin = false
                }
                return .none

            case .versionCheckResponse(.success(let release)):
                if let currentVersion = state.currentVersion,
                   release.isNewer(than: currentVersion) {
                    state.availableUpdate = release.version
                } else {
                    state.availableUpdate = nil
                }
                return .none

            case .versionCheckResponse(.failure):
                return .none
            }
        }
    }

    // MARK: - Private

    private func checkForUpdates() -> Effect<Action> {
        .run { send in
            await send(
                .versionCheckResponse(
                    Result { try await versionClient.fetchLatestRelease() }
                )
            )
        }
    }

    private func fetchUsage(state: inout State) -> Effect<Action> {
        state.isLoading = true
        return .run { send in
            do {
                let token = try apiClient.readToken()
                let usage = try await apiClient.fetchUsage(token)
                await send(.usageResponse(.success(usage)))
                await send(.profileResponse(Result { try await apiClient.fetchProfile(token) }))
            } catch {
                await send(.usageResponse(.failure(error)))
            }
        }
    }

    private func refreshAndRestartTimer(state: inout State) -> Effect<Action> {
        .merge(
            fetchUsage(state: &state),
            checkForUpdates(),
            .run { send in
                for await _ in clock.timer(interval: .seconds(15 * 60)) {
                    await send(.timerTicked)
                }
            }
            .cancellable(id: CancelID.timer, cancelInFlight: true)
        )
    }
}
