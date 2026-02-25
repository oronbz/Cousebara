import ComposableArchitecture
import Foundation
import Sharing

@Reducer
struct PopoverFeature {
    @ObservableState
    struct State: Equatable {
        @Presents var auth: AuthFeature.State?
        var availableUpdate: String?
        var currentVersion: String?
        var error: String?
        var isLoading = false
        var lastUpdated: Date?
        var login: String?
        var needsAuth = false
        var plan: String?
        var resetDate: String?
        var showCopiedConfirmation = false
        @Shared(.appStorage("showPercentageInMenuBar")) var showPercentage = false
        @Shared(.appStorage("showRemainingInsteadOfUsed")) var showRemaining = false
        var usage: QuotaSnapshot?
    }

    enum Action: BindableAction {
        case auth(PresentationAction<AuthFeature.Action>)
        case binding(BindingAction<State>)
        case bundleVersionCheckTicked
        case copiedConfirmationDismissed
        case onAppLaunch
        case onAppear
        case quitButtonTapped
        case refreshButtonTapped
        case retryButtonTapped
        case timerTicked
        case updateBannerTapped
        case usageResponse(Result<CopilotUserResponse, any Error>)
        case versionCheckResponse(Result<GitHubRelease, any Error>)
    }

    enum CancelID {
        case bundleMonitor
        case copiedConfirmation
        case timer
    }

    @Dependency(CopilotAPIClient.self) var apiClient
    @Dependency(AppTerminator.self) var appTerminator
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(VersionClient.self) var versionClient

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .auth(.presented(.delegate(.authenticated))):
                state.auth = nil
                state.needsAuth = false
                return fetchUsage(state: &state)

            case .auth:
                return .none

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

            case .onAppLaunch:
                state.currentVersion = versionClient.currentVersion()
                return .merge(
                    refreshAndRestartTimer(state: &state),
                    .run { send in
                        for await _ in clock.timer(interval: .seconds(15)) {
                            await send(.bundleVersionCheckTicked)
                        }
                    }
                    .cancellable(id: CancelID.bundleMonitor, cancelInFlight: true)
                )

            case .onAppear:
                return refreshAndRestartTimer(state: &state)

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

            case .usageResponse(.success(let response)):
                state.isLoading = false
                state.usage = response.quotaSnapshots?.premiumInteractions
                state.login = response.login
                state.plan = response.copilotPlan
                state.resetDate = response.quotaResetDate
                state.lastUpdated = now
                state.error = nil
                state.needsAuth = false
                return .none

            case .usageResponse(.failure(let error)):
                state.isLoading = false
                if let copilotError = error as? CopilotError, copilotError.isAuthError {
                    state.error = copilotError.localizedDescription
                    state.needsAuth = true
                    state.auth = AuthFeature.State()
                } else {
                    state.error = error.localizedDescription
                    state.needsAuth = false
                }
                return .none

            case .versionCheckResponse(.success(let release)):
                if let currentVersion = state.currentVersion,
                   release.isNewer(than: currentVersion)
                {
                    state.availableUpdate = release.version
                } else {
                    state.availableUpdate = nil
                }
                return .none

            case .versionCheckResponse(.failure):
                return .none
            }
        }
        .ifLet(\.$auth, action: \.auth) {
            AuthFeature()
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
            await send(
                .usageResponse(
                    Result {
                        let token = try apiClient.readToken()
                        return try await apiClient.fetchUsage(token)
                    }
                )
            )
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
