import ComposableArchitecture
import Sharing
import SwiftUI

struct PopoverView: View {
    @Bindable var store: StoreOf<PopoverFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if store.needsLogin {
                needsLoginView
                Divider()
                quitButton
            } else if let error = store.error {
                errorView(error)
                Divider()
                quitButton
            } else if let session = store.session, let weekly = store.weekly {
                windowSection(
                    title: "Session",
                    subtitle: "5-hour window",
                    window: session,
                    pace: nil
                )
                Divider()
                windowSection(
                    title: "Weekly",
                    subtitle: "7-day window",
                    window: weekly,
                    pace: store.weeklyPace
                )
                Divider()
                settingsSection
                if store.availableUpdate != nil {
                    Divider()
                    updateBanner
                }
                Divider()
                footerSection
            } else {
                loadingView
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image("ClaudeIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Cousebara - Claude Usage")
                    .font(.headline)

                if let profile = store.profile {
                    let name = profile.displayName ?? profile.email ?? ""
                    let plan = profile.planLabel ?? ""
                    let line = [name, plan].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !line.isEmpty {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: - Window Section

    private func windowSection(
        title: String,
        subtitle: String,
        window: UsageWindow,
        pace: PaceReserve?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(percentText(window))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(window.level.color)
            }

            WindowProgressBar(window: window, showRemaining: store.showRemaining, pace: pace)
                .frame(height: 10)

            HStack {
                if let resetsAt = window.resetsAt {
                    Text("Resets \(resetsAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let pace {
                    HStack(spacing: 3) {
                        Image(systemName: pace.isUnderPace
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(String(
                            format: "%.0f%% %@",
                            pace.absoluteReserve,
                            pace.isUnderPace ? "under pace" : "over pace"
                        ))
                        .font(.caption2)
                    }
                    .foregroundStyle(pace.isUnderPace ? .green : .orange)
                }
            }
        }
    }

    private func percentText(_ window: UsageWindow) -> String {
        store.showRemaining
            ? String(format: "%.0f%% left", window.percentRemaining)
            : String(format: "%.0f%% used", window.percentUsed)
    }

    // MARK: - Needs Login

    private var needsLoginView: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Log in with Claude Code first, then Refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Refresh") { store.send(.retryButtonTapped) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Error

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.yellow)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { store.send(.retryButtonTapped) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading usage data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Show Percentage in Menu Bar", isOn: Binding(store.$showPercentage))
                .font(.caption)
                .toggleStyle(.checkbox)

            Toggle("Show Remaining Instead of Used", isOn: Binding(store.$showRemaining))
                .font(.caption)
                .toggleStyle(.checkbox)

            Toggle("Launch at Login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.send(.launchAtLoginToggled($0)) }
            ))
            .font(.caption)
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Update Banner

    private var updateBanner: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.body)

                VStack(alignment: .leading, spacing: 1) {
                    if let version = store.availableUpdate {
                        Text("Update available: v\(version)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text("Paste in Terminal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                store.send(.updateBannerTapped)
            } label: {
                HStack(spacing: 3) {
                    if store.showCopiedConfirmation {
                        Image(systemName: "checkmark")
                        Text("Copied!")
                    } else {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(store.showCopiedConfirmation ? .green : nil)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let lastUpdated = store.lastUpdated {
                    let versionPrefix = if let v = store.currentVersion { "v\(v) · " } else { "" }
                    (Text("\(versionPrefix)") + Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let version = store.currentVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button("Refresh") { store.send(.refreshButtonTapped) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Quit") { store.send(.quitButtonTapped) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    // MARK: - Quit Button

    private var quitButton: some View {
        HStack {
            Spacer()
            Button("Quit") { store.send(.quitButtonTapped) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Window Progress Bar

struct WindowProgressBar: View {
    let window: UsageWindow
    let showRemaining: Bool
    var pace: PaceReserve?

    private let cornerRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let height = geometry.size.height
            let fraction = showRemaining ? window.remainingFraction : window.fraction
            let fillWidth = CGFloat(fraction) * totalWidth

            ZStack(alignment: showRemaining ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: totalWidth, height: height)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(window.level.color)
                    .frame(width: fillWidth, height: height)

                if let pace {
                    let tickFraction = CGFloat(pace.percentTimeElapsed / 100)
                    let tickX = showRemaining
                        ? totalWidth * (1 - tickFraction)
                        : totalWidth * tickFraction
                    Rectangle()
                        .fill(Color.primary.opacity(0.6))
                        .frame(width: 1.5, height: height + 4)
                        .position(x: tickX, y: height / 2)
                }
            }
        }
    }
}

// MARK: - Previews

private func makePreviewStore(
    sessionUtil: Double,
    weeklyUtil: Double,
    availableUpdate: String? = nil
) -> StoreOf<PopoverFeature> {
    var initialState = PopoverFeature.State()
    if availableUpdate != nil { initialState.currentVersion = "0.0.0" }
    return Store(initialState: initialState) {
        PopoverFeature()
    } withDependencies: {
        $0[ClaudeAPIClient.self].readToken = { "preview-token" }
        $0[ClaudeAPIClient.self].fetchUsage = { _ in
            ClaudeUsage(
                session: UsageWindow(utilization: sessionUtil, resetsAt: Date().addingTimeInterval(2 * 3600), length: UsageWindow.sessionLength),
                weekly: UsageWindow(utilization: weeklyUtil, resetsAt: Date().addingTimeInterval(4 * 86400), length: UsageWindow.weeklyLength)
            )
        }
        $0[ClaudeAPIClient.self].fetchProfile = { _ in
            ClaudeProfile(displayName: "Oron", email: "oron@example.com", orgName: "Gett", planLabel: "Max 5X")
        }
        if let availableUpdate {
            $0[VersionClient.self].currentVersion = { "0.0.0" }
            $0[VersionClient.self].fetchLatestRelease = { GitHubRelease(tagName: "v\(availableUpdate)", htmlUrl: "") }
        }
    }
}

#Preview("Low usage") {
    PopoverView(store: makePreviewStore(sessionUtil: 25, weeklyUtil: 18))
}

#Preview("Mixed usage") {
    PopoverView(store: makePreviewStore(sessionUtil: 90, weeklyUtil: 55))
}

#Preview("Maxed session") {
    PopoverView(store: makePreviewStore(sessionUtil: 100, weeklyUtil: 70))
}

#Preview("Update available") {
    PopoverView(store: makePreviewStore(sessionUtil: 40, weeklyUtil: 30, availableUpdate: "2.0.0"))
}

#Preview("Needs login") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { throw ClaudeError.noToken }
        }
    )
}

#Preview("Error") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[ClaudeAPIClient.self].readToken = { "preview-token" }
            $0[ClaudeAPIClient.self].fetchUsage = { _ in throw ClaudeError.apiError }
            $0[ClaudeAPIClient.self].fetchProfile = { _ in throw ClaudeError.apiError }
        }
    )
}
