import AppKit

enum DisplayMode: String {
    case auto = "auto"
    case manual = "manual"
}

enum DisplayStyle: String, CaseIterable, Identifiable {
    case compact = "compact"
    case medium = "medium"
    case large = "large"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact (dot)"
        case .medium: return "Medium (label)"
        case .large: return "Large (label + speeds)"
        }
    }
}

final class PillRenderer {
    var displayStyle: DisplayStyle {
        get {
            DisplayStyle(rawValue: UserDefaults.standard.string(forKey: "DisplayStyle") ?? "medium") ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "DisplayStyle")
        }
    }

    var displayMode: DisplayMode {
        get {
            DisplayMode(rawValue: UserDefaults.standard.string(forKey: "DisplayMode") ?? "auto") ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "DisplayMode")
        }
    }

    var fontSize: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: "FontSize").clamped(to: 8...24, default: 14)) }
        set { UserDefaults.standard.set(Float(newValue), forKey: "FontSize") }
    }

    var effectiveDisplayStyle: DisplayStyle {
        guard displayMode == .auto else { return displayStyle }
        switch DisplayDetector.classifyMenuBarDisplay() {
        case .compact: return .compact
        case .medium: return .medium
        case .large: return .large
        }
    }

    func render(status: EthernetStatus) -> NSImage {
        switch effectiveDisplayStyle {
        case .compact:
            return renderCompact(status: status)
        case .medium:
            return renderMedium(status: status)
        case .large:
            return renderLarge(status: status)
        }
    }

    // MARK: - Compact (dot only)

    private func renderCompact(status: EthernetStatus) -> NSImage {
        let dotSize: CGFloat = 6
        let height: CGFloat = 18
        let padding: CGFloat = 2

        let image = NSImage(size: NSSize(width: dotSize + padding * 2, height: height), flipped: false) { rect in
            let dotRect = NSRect(x: padding, y: (height - dotSize) / 2, width: dotSize, height: dotSize)
            let path = NSBezierPath(ovalIn: dotRect)

            if status.isConnected {
                NSColor.systemGreen.setFill()
                path.fill()
            } else {
                NSColor.gray.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Medium (dot + label in pill)

    private func renderMedium(status: EthernetStatus) -> NSImage {
        let font = berkeleyMono(size: fontSize)
        let dotSize: CGFloat = 6
        let spacing: CGFloat = 6
        let pillPadH: CGFloat = 6
        let pillPadV: CGFloat = 2
        let cornerRadius: CGFloat = 4

        let text = status.connectionType?.label ?? "ENET"
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: textAttrs)

        let contentWidth = dotSize + spacing + textSize.width
        let totalWidth = contentWidth + pillPadH * 2
        let pillHeight = textSize.height + pillPadV * 2
        let height = max(18, ceil(pillHeight))

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: false) { rect in
            // Draw pill outline
            let pillRect = NSRect(
                x: 0.5,
                y: (rect.height - pillHeight) / 2,
                width: totalWidth - 1,
                height: pillHeight
            )
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()

            // Draw dot
            let dotX = pillPadH
            let dotY = (rect.height - dotSize) / 2
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            let dotPath = NSBezierPath(ovalIn: dotRect)

            if status.isConnected {
                NSColor.systemGreen.setFill()
                dotPath.fill()
            } else {
                NSColor.gray.setStroke()
                dotPath.lineWidth = 1.2
                dotPath.stroke()
            }

            // Draw text
            let textX = pillPadH + dotSize + spacing
            let textY = (rect.height - textSize.height) / 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Large (dot + label + speeds in pill)

    private func renderLarge(status: EthernetStatus) -> NSImage {
        let font = berkeleyMono(size: fontSize)
        let dotSize: CGFloat = 6
        let spacing: CGFloat = 6
        let pillPadH: CGFloat = 6
        let pillPadV: CGFloat = 2
        let cornerRadius: CGFloat = 4

        let label = status.connectionType?.label ?? "ENET"
        let showSpeeds = UserDefaults.standard.object(forKey: "ShowSpeeds") as? Bool ?? true
        var text = label
        if status.isConnected && showSpeeds {
            let up = formatSpeed(status.uploadBytesPerSec)
            let down = formatSpeed(status.downloadBytesPerSec)
            text = "\(label) \u{2191}\(up) \u{2193}\(down)"
        }

        let textAttrs: [NSAttributedString.Key: Any] = [.font: font]

        // Measure against a worst-case reference string so the pill never resizes
        let refText = "WIFI \u{2191}999M \u{2193}999M"
        let refSize = (refText as NSString).size(withAttributes: textAttrs)
        let textSize = (text as NSString).size(withAttributes: textAttrs)

        let contentWidth = dotSize + spacing + max(textSize.width, refSize.width)
        let totalWidth = contentWidth + pillPadH * 2
        let pillHeight = textSize.height + pillPadV * 2
        let height = max(18, ceil(pillHeight))

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: false) { rect in
            // Draw pill outline
            let pillRect = NSRect(
                x: 0.5,
                y: (rect.height - pillHeight) / 2,
                width: totalWidth - 1,
                height: pillHeight
            )
            let pill = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            pill.lineWidth = 1.0
            pill.stroke()

            // Draw dot
            let dotX = pillPadH
            let dotY = (rect.height - dotSize) / 2
            let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            let dotPath = NSBezierPath(ovalIn: dotRect)

            if status.isConnected {
                NSColor.systemGreen.setFill()
                dotPath.fill()
            } else {
                NSColor.gray.setStroke()
                dotPath.lineWidth = 1.2
                dotPath.stroke()
            }

            // Draw text
            let textX = pillPadH + dotSize + spacing
            let textY = (rect.height - textSize.height) / 2
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Speed Formatting

    private func formatSpeed(_ bytesPerSec: UInt64) -> String {
        let b = Double(bytesPerSec)
        if b < 1024 {
            return String(format: "%3.0fB", b)
        } else if b < 1024 * 1024 {
            return String(format: "%3.0fK", b / 1024)
        } else if b < 1024 * 1024 * 1024 {
            return String(format: "%3.0fM", b / (1024 * 1024))
        } else {
            return String(format: "%3.0fG", b / (1024 * 1024 * 1024))
        }
    }

    // MARK: - Font

    private func berkeleyMono(size: CGFloat) -> NSFont {
        NSFont(name: "Berkeley Mono", size: size)
            ?? NSFont(name: "BerkeleyMono-Regular", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>, default defaultValue: Float) -> Float {
        if self == 0 { return defaultValue }
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
