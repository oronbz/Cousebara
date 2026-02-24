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
/// NSImage using the template image approach. macOS automatically tints
/// template images white on dark menu bars and black on light menu bars.
/// All visual differentiation is expressed through alpha values only.
enum MenuBarImageRenderer {
    private static let iconSize: CGFloat = 16
    private static let barWidth: CGFloat = 8
    private static let barHeight: CGFloat = 16
    private static let barCornerRadius: CGFloat = 1
    private static let spacing: CGFloat = 2
    private static let scale: CGFloat = 2

    /// Inner padding between the track background and the fill
    private static let fillPadding: CGFloat = 1
    private static let fillCornerRadius: CGFloat = 0

    // Alpha values for the monochrome template image
    private static let trackAlpha: CGFloat = 0.30
    private static let fillAlpha: CGFloat = 1.0

    static func render(usage: QuotaSnapshot?) -> NSImage {
        let hasBar = usage != nil
        let totalWidth = iconSize + (hasBar ? spacing + barWidth : 0)
        let totalHeight = iconSize // fixed to icon size — bar is vertically centered within

        let image = NSImage(size: NSSize(width: totalWidth, height: totalHeight))

        // Create a 2x bitmap representation for crisp rendering on Retina
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(totalWidth * scale),
            pixelsHigh: Int(totalHeight * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) {
            rep.size = NSSize(width: totalWidth, height: totalHeight) // points
            image.addRepresentation(rep)

            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx

                let baseColor = NSColor.black

                // Draw icon
                if let copilotIcon = NSImage(named: "CopilotIcon") {
                    let tinted = tintedImage(copilotIcon, color: baseColor.withAlphaComponent(fillAlpha))
                    // Aspect-fit the icon into the iconSize square
                    let iconAspect = copilotIcon.size.width / copilotIcon.size.height
                    let drawWidth: CGFloat
                    let drawHeight: CGFloat
                    if iconAspect > 1 {
                        drawWidth = iconSize
                        drawHeight = iconSize / iconAspect
                    } else {
                        drawHeight = iconSize
                        drawWidth = iconSize * iconAspect
                    }
                    let iconX = (iconSize - drawWidth) / 2
                    let iconY = (totalHeight - drawHeight) / 2
                    tinted.draw(in: NSRect(x: iconX, y: iconY, width: drawWidth, height: drawHeight))
                }

                // Draw progress bar
                if let usage {
                    let barX = iconSize + spacing
                    let barY = (totalHeight - barHeight) / 2
                    drawProgressBar(
                        at: NSPoint(x: barX, y: barY),
                        usage: usage,
                        baseColor: baseColor
                    )
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Template image — macOS auto-tints based on menu bar appearance
        image.isTemplate = true
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

    private static func drawProgressBar(at origin: NSPoint, usage: QuotaSnapshot, baseColor: NSColor) {
        // Background track
        let bgRect = NSRect(x: origin.x, y: origin.y, width: barWidth, height: barHeight)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: barCornerRadius, yRadius: barCornerRadius)
        baseColor.withAlphaComponent(trackAlpha).setFill()
        bgPath.fill()

        // Inner fill area (inset by padding on all sides)
        let innerRect = bgRect.insetBy(dx: fillPadding, dy: fillPadding)
        let innerHeight = innerRect.height

        // Compute fill height — clamped to inner area
        let fillFraction: CGFloat
        if usage.isOverLimit {
            fillFraction = 1.0 // always full when over limit
        } else {
            fillFraction = CGFloat(usage.normalFraction)
        }

        let filledHeight = fillFraction * innerHeight
        guard filledHeight > 0 else { return }

        let fillRect = NSRect(
            x: innerRect.origin.x,
            y: innerRect.origin.y,
            width: innerRect.width,
            height: filledHeight
        )

        // Clip to the inner rounded rect so fill stays within padded bounds
        NSGraphicsContext.current?.cgContext.saveGState()
        let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: fillCornerRadius, yRadius: fillCornerRadius)
        innerPath.addClip()
        baseColor.withAlphaComponent(fillAlpha).setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.current?.cgContext.restoreGState()
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
