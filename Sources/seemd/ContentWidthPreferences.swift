import Foundation

/// App-layer UserDefaults-backed storage for the preview content width and the
/// "fill window width" toggle. Kept out of `RenderContext` on purpose: width is
/// pure layout (the document container frame), not a rendering input, so
/// changing it must not invalidate the per-block render tree.
enum ContentWidthPreferences {

    /// UserDefaults keys (app-layer namespace).
    static let widthKey = "seemd.contentWidth"
    static let fillKey = "seemd.fillWindowWidth"

    /// Allowed content-width range / step (matches the Settings slider).
    static let minWidth: Double = 600
    static let maxWidth: Double = 1400
    static let defaultWidth: Double = 760

    /// Clamped content width in points. Falls back to `defaultWidth` when unset.
    static func width(from defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.object(forKey: widthKey) as? Double ?? defaultWidth
        return min(max(stored, minWidth), maxWidth)
    }

    static func setWidth(_ value: Double, in defaults: UserDefaults = .standard) {
        let clamped = min(max(value, minWidth), maxWidth)
        defaults.set(clamped, forKey: widthKey)
    }

    /// When true the document uses the full available width (minus the existing
    /// horizontal padding) instead of a max cap.
    static func fillWindowWidth(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: fillKey)
    }

    static func setFillWindowWidth(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: fillKey)
    }
}
