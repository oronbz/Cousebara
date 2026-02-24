import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let usage: QuotaSnapshot?

    var body: some View {
        Image(nsImage: MenuBarImageRenderer.render(usage: usage))
    }
}

// MARK: - Combined menu bar image renderer

/// Renders the entire menu bar label (icon + progress bar) as a single
/// NSImage. MenuBarExtra labels only reliably display a single Image —
/// HStacks and multiple Images are silently ignored.
enum MenuBarImageRenderer {
    private static let iconSize: CGFloat = 16
    private static let barWidth: CGFloat = 5
    private static let barHeight: CGFloat = 12
    private static let barCornerRadius: CGFloat = 1.5
    private static let spacing: CGFloat = 2
    /// Maximum overshoot height so the bar doesn't exceed menu bar bounds
    private static let maxOvershoot: CGFloat = 4

    static func render(usage: QuotaSnapshot?) -> NSImage {
        let barTotalHeight: CGFloat
        if let usage, usage.isOverLimit {
            let overshoot = min(min(CGFloat(usage.overageFraction), 1.0) * barHeight, maxOvershoot)
            barTotalHeight = barHeight + overshoot
        } else {
            barTotalHeight = barHeight
        }

        let hasBar = usage != nil
        let totalWidth = iconSize + (hasBar ? spacing + barWidth : 0)
        let totalHeight = iconSize // fixed to icon size — bar is vertically centered within

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { _ in
            // Draw icon tinted for menu bar (white in dark mode)
            if let copilotIcon = NSImage(named: "CopilotIcon") {
                let tinted = tintedImage(copilotIcon, color: .white)
                // Aspect-fit the icon into the iconSize square
                let iconAspect = copilotIcon.size.width / copilotIcon.size.height
                let drawWidth: CGFloat
                let drawHeight: CGFloat
                if iconAspect > 1 {
                    // Wider than tall
                    drawWidth = iconSize
                    drawHeight = iconSize / iconAspect
                } else {
                    // Taller than wide
                    drawHeight = iconSize
                    drawWidth = iconSize * iconAspect
                }
                let iconX = (iconSize - drawWidth) / 2
                let iconY = (totalHeight - drawHeight) / 2
                let iconRect = NSRect(x: iconX, y: iconY, width: drawWidth, height: drawHeight)
                tinted.draw(in: iconRect)
            }

            // Draw progress bar
            if let usage {
                let barX = iconSize + spacing
                let barY = (totalHeight - barTotalHeight) / 2
                drawProgressBar(at: NSPoint(x: barX, y: barY), usage: usage, barTotalHeight: barTotalHeight)
            }

            return true
        }
        // Must NOT be template so colors are preserved
        image.isTemplate = false
        return image
    }

    /// Creates a copy of the image filled with the given color, preserving alpha.
    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
    }

    private static func drawProgressBar(at origin: NSPoint, usage: QuotaSnapshot, barTotalHeight: CGFloat) {
        // Background track
        let bgRect = NSRect(x: origin.x, y: origin.y, width: barWidth, height: barTotalHeight)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: barCornerRadius, yRadius: barCornerRadius)
        NSColor.white.withAlphaComponent(0.25).setFill()
        bgPath.fill()

        if usage.isOverLimit {
            // Orange normal portion (bottom, full barHeight)
            let orangeRect = NSRect(x: origin.x, y: origin.y, width: barWidth, height: barHeight)
            let orangePath = NSBezierPath(roundedRect: orangeRect, xRadius: barCornerRadius, yRadius: barCornerRadius)
            NSColor.orange.setFill()
            orangePath.fill()

            // Red overshoot portion (top)
            let overshootHeight = barTotalHeight - barHeight
            if overshootHeight > 0 {
                let redRect = NSRect(x: origin.x, y: origin.y + barHeight, width: barWidth, height: overshootHeight)
                let redPath = NSBezierPath(roundedRect: redRect, xRadius: barCornerRadius, yRadius: barCornerRadius)
                NSColor.red.setFill()
                redPath.fill()
            }
        } else {
            // Normal fill from bottom
            let filledHeight = CGFloat(usage.normalFraction) * barHeight
            if filledHeight > 0 {
                let fillRect = NSRect(x: origin.x, y: origin.y, width: barWidth, height: filledHeight)
                let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: barCornerRadius, yRadius: barCornerRadius)
                normalColor(for: usage).setFill()
                fillPath.fill()
            }
        }
    }

    private static func normalColor(for usage: QuotaSnapshot) -> NSColor {
        let fraction = usage.normalFraction
        if fraction < 0.6 {
            return .systemGreen
        } else if fraction < 0.85 {
            return .systemYellow
        } else {
            return .systemOrange
        }
    }
}

// MARK: - SwiftUI wrapper for previews

struct MenuBarProgressBar: View {
    let usage: QuotaSnapshot

    var body: some View {
        Image(nsImage: MenuBarImageRenderer.render(usage: usage))
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
