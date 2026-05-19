import Foundation

/// Pure zoom-scale logic with injectable UserDefaults for testability.
public struct ZoomScale {

    public static let min: Double = 0.5
    public static let max: Double = 3.0
    public static let `default`: Double = 1.0
    public static let step: Double = 0.1

    private static let userDefaultsKey = "seemd.zoomScale"

    // MARK: - Clamp / step

    /// Returns `value` clamped to [min, max].
    public static func clamp(_ value: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    /// Returns the next zoom-in value (current + step), clamped.
    public static func zoomIn(_ current: Double) -> Double {
        clamp(current + step)
    }

    /// Returns the next zoom-out value (current - step), clamped.
    public static func zoomOut(_ current: Double) -> Double {
        clamp(current - step)
    }

    /// Returns the default zoom scale (1.0).
    public static func reset() -> Double {
        `default`
    }

    // MARK: - Persistence

    /// Loads the saved zoom scale from `defaults`, falling back to `default`.
    public static func load(from defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: userDefaultsKey)
        // double(forKey:) returns 0.0 when the key is absent.
        guard stored != 0.0 else { return `default` }
        return clamp(stored)
    }

    /// Persists `value` (clamped) to `defaults`.
    public static func save(_ value: Double, to defaults: UserDefaults = .standard) {
        defaults.set(clamp(value), forKey: userDefaultsKey)
    }
}
