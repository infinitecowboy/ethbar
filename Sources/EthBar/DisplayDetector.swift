import CoreGraphics
import Foundation

enum DisplaySizeClass: String, CaseIterable, Identifiable {
    case compact   // <16" — built-in laptop displays
    case medium    // 16–25" — smaller externals
    case large     // >25" — large externals (4K, ultrawide)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact (<16\")"
        case .medium: return "Medium (16–25\")"
        case .large: return "Large (>25\")"
        }
    }
}

enum DisplayDetector {
    static var override: DisplaySizeClass? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "DisplaySizeClassOverride") else { return nil }
            return DisplaySizeClass(rawValue: raw)
        }
        set {
            if let val = newValue {
                UserDefaults.standard.set(val.rawValue, forKey: "DisplaySizeClassOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "DisplaySizeClassOverride")
            }
        }
    }

    /// Classify the primary display (where the menu bar lives) by physical diagonal size.
    static func classifyMenuBarDisplay() -> DisplaySizeClass {
        if let forced = `override` { return forced }

        let mainID = CGMainDisplayID()
        let physicalSize = CGDisplayScreenSize(mainID) // millimeters

        if physicalSize.width > 0 && physicalSize.height > 0 {
            let diagMM = sqrt(physicalSize.width * physicalSize.width + physicalSize.height * physicalSize.height)
            let diagInches = diagMM / 25.4
            return classify(diagonal: diagInches)
        }

        // Fallback: estimate from logical resolution
        let pixelWidth = CGFloat(CGDisplayPixelsWide(mainID))
        let isBuiltIn = CGDisplayIsBuiltin(mainID) != 0
        if isBuiltIn {
            return .compact
        }
        // Rough heuristic: >2560 logical pixels wide → likely large display
        return pixelWidth > 2560 ? .large : .medium
    }

    private static func classify(diagonal: Double) -> DisplaySizeClass {
        if diagonal < 16 { return .compact }
        if diagonal <= 25 { return .medium }
        return .large
    }
}
