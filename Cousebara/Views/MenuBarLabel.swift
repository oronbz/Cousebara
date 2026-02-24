import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let usage: QuotaSnapshot?
    let showPercentage: Bool

    var body: some View {
        Image(nsImage: menuBarImage)
    }

    private var menuBarImage: NSImage {
        let content = HStack(alignment: .center, spacing: 3) {
            if showPercentage, let usage {
                Text("\(Int(usage.percentUsed))%")
                    .font(.system(size: 12, weight: .medium, design: .default).monospacedDigit())
            }

            Image("github-copilot-icon")
                .resizable()
                .scaledToFit()
                .frame(height: 16)

            if let usage {
                MenuBarProgressBar(usage: usage)
            }
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        guard let cgImage = renderer.cgImage else {
            return NSImage(named: "github-copilot-icon") ?? NSImage()
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width / Int(renderer.scale),
            height: cgImage.height / Int(renderer.scale)
        ))
        image.isTemplate = true
        return image
    }
}

// MARK: - Menu Bar Progress Bar

/// A small vertical progress bar for the menu bar.
/// Uses opacity to match the template image tinting behavior.
struct MenuBarProgressBar: View {
    let usage: QuotaSnapshot

    private let barWidth: CGFloat = 10
    private let barHeight: CGFloat = 18
    private let cornerRadius: CGFloat = 1.5
    private let fillPadding: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            // Background track
            let trackRect = CGRect(origin: .zero, size: size)
            let trackPath = Path(roundedRect: trackRect, cornerRadius: cornerRadius)
            context.opacity = 0.30
            context.fill(trackPath, with: .foreground)
            context.opacity = 1.0

            // Fill area (inset by padding)
            let innerRect = trackRect.insetBy(dx: fillPadding, dy: fillPadding)
            let fillH = fillFraction * innerRect.height
            guard fillH > 0 else { return }

            let fillRect = CGRect(
                x: innerRect.minX,
                y: innerRect.maxY - fillH,
                width: innerRect.width,
                height: fillH
            )
            context.fill(Path(fillRect), with: .foreground)
        }
        .frame(width: barWidth, height: barHeight)
    }

    private var fillFraction: CGFloat {
        if usage.isOverLimit {
            1.0
        } else {
            CGFloat(usage.normalFraction)
        }
    }
}

// MARK: - Previews

#Preview("Low Usage (30%)") {
    MenuBarLabel(usage: .lowUsage, showPercentage: false)
        .padding()
}

#Preview("Medium Usage (65%)") {
    MenuBarLabel(usage: .mediumUsage, showPercentage: false)
        .padding()
}

#Preview("High Usage (90%)") {
    MenuBarLabel(usage: .highUsage, showPercentage: false)
        .padding()
}

#Preview("At Limit (100%)") {
    MenuBarLabel(usage: .atLimit, showPercentage: false)
        .padding()
}

#Preview("Slightly Over (110%)") {
    MenuBarLabel(usage: .slightlyOver, showPercentage: false)
        .padding()
}

#Preview("Over Limit (154%)") {
    MenuBarLabel(usage: .overLimit, showPercentage: false)
        .padding()
}

#Preview("No Data") {
    MenuBarLabel(usage: nil, showPercentage: false)
        .padding()
}

#Preview("With Percentage") {
    HStack(spacing: 16) {
        LabeledContent("30%") { MenuBarLabel(usage: .lowUsage, showPercentage: true) }
        LabeledContent("65%") { MenuBarLabel(usage: .mediumUsage, showPercentage: true) }
        LabeledContent("90%") { MenuBarLabel(usage: .highUsage, showPercentage: true) }
        LabeledContent("100%") { MenuBarLabel(usage: .atLimit, showPercentage: true) }
        LabeledContent("154%") { MenuBarLabel(usage: .overLimit, showPercentage: true) }
    }
    .padding()
}

#Preview("All States") {
    HStack(spacing: 16) {
        LabeledContent("30%") { MenuBarLabel(usage: .lowUsage, showPercentage: false) }
        LabeledContent("65%") { MenuBarLabel(usage: .mediumUsage, showPercentage: false) }
        LabeledContent("90%") { MenuBarLabel(usage: .highUsage, showPercentage: false) }
        LabeledContent("100%") { MenuBarLabel(usage: .atLimit, showPercentage: false) }
        LabeledContent("110%") { MenuBarLabel(usage: .slightlyOver, showPercentage: false) }
        LabeledContent("154%") { MenuBarLabel(usage: .overLimit, showPercentage: false) }
        LabeledContent("N/A") { MenuBarLabel(usage: nil, showPercentage: false) }
    }
    .padding()
}
