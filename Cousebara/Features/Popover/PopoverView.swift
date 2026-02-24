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
                Divider()
                footerSection
            } else {
                loadingView
            }
        }
        .padding(16)
        .frame(width: 280)
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

                Text("\(usage.used) / \(usage.entitlement)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Large progress bar
            PopoverProgressBar(usage: usage)
                .frame(height: 12)
        }
    }

    private func usagePercentText(_ usage: QuotaSnapshot) -> String {
        let percent = usage.percentUsed
        if percent > 100 {
            return String(format: "%.0f%% used", percent)
        }
        return String(format: "%.0f%% used", percent)
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
        Toggle("Show Percentage in Menu Bar", isOn: $store.showPercentage)
            .font(.caption)
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

                if usage.isOverLimit {
                    overLimitFill(totalWidth: totalWidth, height: height)
                } else {
                    normalFill(totalWidth: totalWidth, height: height)
                }
            }
        }
    }

    private func normalFill(totalWidth: CGFloat, height: CGFloat) -> some View {
        let fillWidth = CGFloat(max(0, usage.normalFraction)) * totalWidth
        return RoundedRectangle(cornerRadius: cornerRadius)
            .fill(normalGradient)
            .frame(width: fillWidth, height: height)
    }

    private func overLimitFill(totalWidth: CGFloat, height: CGFloat) -> some View {
        let normalWidth = totalWidth * (1.0 / (1.0 + min(usage.overageFraction, 1.0)))
        let overshootWidth = totalWidth - normalWidth

        return HStack(spacing: 0) {
            // Normal portion (up to 100%)
            Rectangle()
                .fill(Color.orange)
                .frame(width: normalWidth, height: height)

            // Overshoot portion
            Rectangle()
                .fill(Color.red)
                .frame(width: overshootWidth, height: height)
        }
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

private func makeCopilotResponse(
    usage: QuotaSnapshot
) -> CopilotUserResponse {
    CopilotUserResponse(
        login: "oronbz",
        copilotPlan: "enterprise",
        quotaResetDate: "2026-03-01",
        quotaSnapshots: QuotaSnapshots(premiumInteractions: usage)
    )
}

#Preview("Low Usage (30%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .lowUsage)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("Medium Usage (65%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .mediumUsage)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("High Usage (90%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .highUsage)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("At Limit (100%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .atLimit)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("Slightly Over (110%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .slightlyOver)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("Over Limit (154%)") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            let response = makeCopilotResponse(usage: .overLimit)
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in response }
        }
    )
}

#Preview("Loading") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
            $0[CopilotAPIClient.self].fetchUsage = { _ in
                try await Task.sleep(for: .seconds(999))
                throw CancellationError()
            }
        }
    )
}

#Preview("Error") {
    PopoverView(
        store: Store(initialState: PopoverFeature.State()) {
            PopoverFeature()
        } withDependencies: {
            $0[CopilotAPIClient.self].readToken = { "mock-token" }
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
