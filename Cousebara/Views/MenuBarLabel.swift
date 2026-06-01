import AppKit
import SwiftUI

// MARK: - UsageLevel → Color (shared by menu bar + popover)

extension UsageLevel {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .high: .orange
        case .maxed: .red
        }
    }
}

struct MenuBarLabel: View {
    let session: UsageWindow?
    let weekly: UsageWindow?
    let showPercentage: Bool
    let showRemaining: Bool

    // The menu bar image is non-template (so the bar colors survive), which means
    // macOS won't auto-invert the percentage text for dark/light menu bars. Drive
    // its color from the color scheme instead; changing appearance re-runs `body`
    // and regenerates the image with the right baked text color.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: menuBarImage)
    }

    /// Utilization of the most-constrained window (highest used / lowest remaining).
    private var worstUtilization: Double {
        max(session?.utilization ?? 0, weekly?.utilization ?? 0)
    }

    private var percentText: String {
        let value = showRemaining ? max(0, 100 - worstUtilization) : worstUtilization
        return "\(Int(value.rounded()))%"
    }

    private var menuBarImage: NSImage {
        let content = HStack(alignment: .center, spacing: 4) {
            if showPercentage {
                Text(percentText)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            } else {
                Image("ClaudeIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 14)
            }
            MenuBarVerticalBar(window: session, showRemaining: showRemaining)
            MenuBarVerticalBar(window: weekly, showRemaining: showRemaining)
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let cgImage = renderer.cgImage else { return NSImage() }

        let image = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width / Int(renderer.scale),
            height: cgImage.height / Int(renderer.scale)
        ))
        // Colored (not template) so the green/yellow/orange/red signal survives.
        image.isTemplate = false
        return image
    }
}

// MARK: - Menu Bar Vertical Bar

/// A small vertical bar for the menu bar, filled bottom-up and colored by the
/// window's usage level.
struct MenuBarVerticalBar: View {
    let window: UsageWindow?
    let showRemaining: Bool

    private let barWidth: CGFloat = 5
    private let barHeight: CGFloat = 16
    private let cornerRadius: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let trackRect = CGRect(origin: .zero, size: size)
            let trackPath = Path(roundedRect: trackRect, cornerRadius: cornerRadius)
            context.fill(trackPath, with: .color(.gray.opacity(0.4)))

            guard let window else { return }
            // Fill height tracks remaining vs used; color always reflects the
            // usage level (utilization), matching the popover's progress bar.
            let fraction = showRemaining ? window.remainingFraction : window.fraction
            let fillH = CGFloat(fraction) * size.height
            guard fillH > 0 else { return }

            let fillRect = CGRect(
                x: 0,
                y: size.height - fillH,
                width: size.width,
                height: fillH
            )
            context.fill(
                Path(roundedRect: fillRect, cornerRadius: cornerRadius),
                with: .color(window.level.color)
            )
        }
        .frame(width: barWidth, height: barHeight)
    }
}

// MARK: - Previews

private func win(_ util: Double, length: TimeInterval = UsageWindow.sessionLength) -> UsageWindow {
    UsageWindow(utilization: util, resetsAt: Date().addingTimeInterval(3600), length: length)
}

#Preview("Low / Low") {
    MenuBarLabel(session: win(20), weekly: win(15), showPercentage: false, showRemaining: false).padding()
}

#Preview("Session high, Weekly mid") {
    MenuBarLabel(session: win(90), weekly: win(55), showPercentage: false, showRemaining: false).padding()
}

#Preview("With percentage (used)") {
    MenuBarLabel(session: win(90), weekly: win(55), showPercentage: true, showRemaining: false).padding()
}

#Preview("With percentage (remaining)") {
    MenuBarLabel(session: win(90), weekly: win(55), showPercentage: true, showRemaining: true).padding()
}

#Preview("No data") {
    MenuBarLabel(session: nil, weekly: nil, showPercentage: false, showRemaining: false).padding()
}
