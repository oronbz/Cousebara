import ComposableArchitecture
import Sharing
import SwiftUI

struct PopoverView: View {
    @Bindable var store: StoreOf<PopoverFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()

            if let authStore = store.scope(state: \.auth, action: \.auth.presented) {
                AuthView(store: authStore)
                Divider()
                quitButton
            } else if let error = store.error, !store.needsAuth {
                errorView(error)
                Divider()
                quitButton
            } else if let usage = store.usage {
                usageSection(usage)
                Divider()
                detailsSection(usage)
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
        .onAppear {
            store.send(.onAppear)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image("github-copilot-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Copilot Premium Usage")
                    .font(.headline)

                if let login = store.login, let plan = store.plan {
                    Text("\(login) - \(plan)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Usage Section

    private func usageSection(_ usage: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Percentage text
            HStack {
                Text(usagePercentText(usage))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(usageColor(usage))

                Spacer()

                Text(store.showRemaining
                    ? "\(usage.remaining) / \(usage.entitlement)"
                    : "\(usage.used) / \(usage.entitlement)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Large progress bar
            PopoverProgressBar(
                usage: usage,
                showRemaining: store.showRemaining,
                paceReserve: store.paceReserve
            )
            .frame(height: 12)

            // Pace reserve indicator
            if let pace = store.paceReserve {
                HStack(spacing: 4) {
                    Image(systemName: pace.isUnderPace
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(String(
                        format: "%.0f%% %@",
                        pace.absoluteReserve,
                        pace.isUnderPace ? "in reserve" : "over pace"
                    ))
                    .font(.caption)
                }
                .foregroundStyle(pace.isUnderPace ? .green : .orange)
            }
        }
    }

    private func usagePercentText(_ usage: QuotaSnapshot) -> String {
        if store.showRemaining {
            let percent = usage.percentRemaining
            return String(format: "%.0f%% remaining", percent)
        } else {
            return String(format: "%.0f%% used", usage.percentUsed)
        }
    }

    private func usageColor(_ usage: QuotaSnapshot) -> Color {
        if usage.isOverLimit { return .red }
        if usage.normalFraction > 0.85 { return .orange }
        if usage.normalFraction > 0.6 { return .yellow }
        return .green
    }

    // MARK: - Details Section

    private func detailsSection(_ usage: QuotaSnapshot) -> some View {
        VStack(spacing: 6) {
            detailRow("Entitlement", value: "\(usage.entitlement)")
            detailRow("Used", value: "\(usage.used)")

            if usage.isOverLimit {
                detailRow("Over by", value: "\(usage.overageAmount)", color: .red)
                detailRow("Overage allowed", value: usage.overagePermitted ? "Yes" : "No")
            } else {
                detailRow("Remaining", value: "\(usage.remaining)")
            }

            if let resetDate = store.resetDate {
                detailRow("Resets", value: formattedResetDate(resetDate))
            }

            if let pace = store.paceReserve {
                detailRow(
                    "Pace",
                    value: pace.isUnderPace ? "Lasts until reset" : "May exceed limit",
                    color: pace.isUnderPace ? .green : .orange
                )
            }
        }
    }

    private func detailRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }

    private func formattedResetDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium

        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0

        let dateStr = displayFormatter.string(from: date)
        if days > 0 {
            return "\(dateStr) (in \(days) days)"
        } else if days == 0 {
            return "\(dateStr) (today)"
        } else {
            return dateStr
        }
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

            Button("Retry") {
                store.send(.retryButtonTapped)
            }
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
            Toggle("Show Percentage in Menu Bar", isOn: $store.showPercentage)
                .font(.caption)
                .toggleStyle(.checkbox)

            Toggle("Show Remaining Instead of Used", isOn: $store.showRemaining)
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
                    (Text("\(versionPrefix) ") + Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if let version = store.currentVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button("Refresh") {
                store.send(.refreshButtonTapped)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Quit") {
                store.send(.quitButtonTapped)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Quit Button

    private var quitButton: some View {
        HStack {
            Spacer()
            Button("Quit") {
                store.send(.quitButtonTapped)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

// MARK: - Popover Progress Bar

struct PopoverProgressBar: View {
    let usage: QuotaSnapshot
    let showRemaining: Bool
    var paceReserve: PaceReserve?

    private let cornerRadius: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: totalWidth, height: height)

                if showRemaining {
                    remainingFill(totalWidth: totalWidth, height: height)
                } else if usage.isOverLimit {
                    overLimitFill(totalWidth: totalWidth, height: height)
                } else {
                    normalFill(totalWidth: totalWidth, height: height)
                }

                // Pace tick mark
                if let pace = paceReserve {
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

    private func remainingFill(totalWidth: CGFloat, height: CGFloat) -> some View {
        let fillWidth = CGFloat(usage.remainingFraction) * totalWidth
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(normalGradient)
            .frame(width: fillWidth, height: height)
    }

    private func normalFill(totalWidth: CGFloat, height: CGFloat) -> some View {
        let fillWidth = CGFloat(max(0, usage.normalFraction)) * totalWidth
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(normalGradient)
            .frame(width: fillWidth, height: height)
    }

    private func overLimitFill(totalWidth: CGFloat, height: CGFloat) -> some View {
        Rectangle()
                .fill(Color.red)
                .frame(width: totalWidth, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var normalGradient: LinearGradient {
        let fraction = usage.normalFraction
        let color: Color = if fraction < 0.6 {
            .green
        } else if fraction < 0.85 {
            .yellow
        } else {
            .orange
        }
        return LinearGradient(
            colors: [color.opacity(0.8), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Previews

private func makePreviewResponse(
    usage: QuotaSnapshot,
    login: String = "oronbz",
    plan: String = "enterprise",
    resetDate: String = "2026-03-15"
) -> CopilotUserResponse {
    CopilotUserResponse(
        login: login,
        copilotPlan: plan,
        quotaResetDate: resetDate,
        quotaSnapshots: QuotaSnapshots(premiumInteractions: usage)
    )
}

private func makePreviewStore(
    usage: QuotaSnapshot,
    availableUpdate: String? = nil,
    previewDate: Date = Date()
) -> StoreOf<PopoverFeature> {
    let response = makePreviewResponse(usage: usage)
    var initialState = PopoverFeature.State()
    if availableUpdate != nil {
        initialState.currentVersion = "0.0.0"
    }
    return Store(initialState: initialState) {
        PopoverFeature()
    } withDependencies: {
        $0[CopilotAPIClient.self].readToken = { "preview-token" }
        $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        $0.date = .constant(previewDate)
        if let availableUpdate {
            $0[VersionClient.self].currentVersion = { "0.0.0" }
            $0[VersionClient.self].fetchLatestRelease = {
                GitHubRelease(tagName: "v\(availableUpdate)", htmlUrl: "")
            }
        }
    }
}

#Preview("Low Usage (30%)") {
    PopoverView(store: makePreviewStore(usage: .lowUsage))
}

#Preview("Medium Usage (65%)") {
    PopoverView(store: makePreviewStore(usage: .mediumUsage))
}

#Preview("High Usage (90%)") {
    PopoverView(store: makePreviewStore(usage: .highUsage))
}

#Preview("At Limit (100%)") {
    PopoverView(store: makePreviewStore(usage: .atLimit))
}

#Preview("Slightly Over (110%)") {
    PopoverView(store: makePreviewStore(usage: .slightlyOver))
}

#Preview("Over Limit (154%)") {
    PopoverView(store: makePreviewStore(usage: .overLimit))
}

#Preview("Loading") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "preview-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in
                try await Task.sleep(for: .seconds(999))
                return makePreviewResponse(usage: .mediumUsage)
            }
        }
    )
}

#Preview("Error") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "preview-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in throw CopilotError.apiError }
        }
    )
}

#Preview("Needs Auth") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { throw CopilotError.tokenFileMissing }
        }
    )
}

#Preview("Update Available") {
    PopoverView(store: makePreviewStore(usage: .mediumUsage, availableUpdate: "2.0.0"))
}
#Preview("Under Pace (30% used, mid-month)") {
    PopoverView(store: makePreviewStore(usage: .lowUsage))
}

#Preview("Over Pace (90% used, mid-month)") {
    PopoverView(store: makePreviewStore(usage: .highUsage))
}

