import SwiftUI

struct MenuBarLabel: View {
    let usage: QuotaSnapshot?

    var body: some View {
        HStack(spacing: 3) {
            Image("CopilotIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            if let usage {
                MenuBarProgressBar(usage: usage)
            }
        }
    }
}

struct MenuBarProgressBar: View {
    let usage: QuotaSnapshot

    private let barWidth: CGFloat = 6
    private let barHeight: CGFloat = 16
    private let cornerRadius: CGFloat = 1.5

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background track
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.primary.opacity(0.2))
                .frame(width: barWidth, height: totalHeight)

            if usage.isOverLimit {
                overLimitFill
            } else {
                normalFill
            }
        }
        .frame(width: barWidth, height: totalHeight)
    }

    private var totalHeight: CGFloat {
        if usage.isOverLimit {
            let overshoot = min(usage.overageFraction, 1.0) * barHeight
            return barHeight + overshoot
        }
        return barHeight
    }

    // MARK: - Normal

    private var normalFill: some View {
        let filledHeight = CGFloat(usage.normalFraction) * barHeight
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(normalColor)
                .frame(width: barWidth, height: filledHeight)
        }
    }

    // MARK: - Over Limit

    private var overLimitFill: some View {
        let overshootHeight = CGFloat(min(usage.overageFraction, 1.0)) * barHeight

        return VStack(spacing: 0) {
            // Red overshoot portion (top)
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius
            )
            .fill(Color.red)
            .frame(width: barWidth, height: overshootHeight)

            // Orange normal portion (bottom, full)
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0
            )
            .fill(Color.orange)
            .frame(width: barWidth, height: barHeight)
        }
    }

    private var normalColor: Color {
        let fraction = usage.normalFraction
        if fraction < 0.6 {
            return .green
        } else if fraction < 0.85 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// MARK: - Previews

#Preview("Low Usage (30%)") {
    MenuBarLabel(usage: .lowUsage)
        .padding()
}

#Preview("Medium Usage (65%)") {
    MenuBarLabel(usage: .mediumUsage)
        .padding()
}

#Preview("High Usage (90%)") {
    MenuBarLabel(usage: .highUsage)
        .padding()
}

#Preview("At Limit (100%)") {
    MenuBarLabel(usage: .atLimit)
        .padding()
}

#Preview("Slightly Over (110%)") {
    MenuBarLabel(usage: .slightlyOver)
        .padding()
}

#Preview("Over Limit (154%)") {
    MenuBarLabel(usage: .overLimit)
        .padding()
}

#Preview("No Data") {
    MenuBarLabel(usage: nil)
        .padding()
}

#Preview("All States") {
    HStack(spacing: 16) {
        LabeledContent("30%") { MenuBarLabel(usage: .lowUsage) }
        LabeledContent("65%") { MenuBarLabel(usage: .mediumUsage) }
        LabeledContent("90%") { MenuBarLabel(usage: .highUsage) }
        LabeledContent("100%") { MenuBarLabel(usage: .atLimit) }
        LabeledContent("110%") { MenuBarLabel(usage: .slightlyOver) }
        LabeledContent("154%") { MenuBarLabel(usage: .overLimit) }
        LabeledContent("N/A") { MenuBarLabel(usage: nil) }
    }
    .padding()
}
