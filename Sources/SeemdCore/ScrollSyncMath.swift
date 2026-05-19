import Foundation

/// Pure, deterministic scroll-sync mapping math.
///
/// Converts a driver scroll position into a follower scroll position using
/// heading-anchored interpolation when at least two aligned heading pairs are
/// available, falling back to proportional mapping otherwise.
public enum ScrollSyncMath {

    // MARK: - Public API

    /// Maps a driver scroll offset to the corresponding follower scroll offset.
    ///
    /// - Parameters:
    ///   - driverTop: Current scroll offset of the driver (content-space Y of the viewport top).
    ///   - driverContentHeight: Total content height of the driver scroll view.
    ///   - driverViewportHeight: Visible height of the driver scroll view.
    ///   - driverHeadingYs: Content-space Y offsets of each heading in the driver, document order.
    ///   - followerContentHeight: Total content height of the follower scroll view.
    ///   - followerViewportHeight: Visible height of the follower scroll view.
    ///   - followerHeadingYs: Content-space Y offsets of each heading in the follower, document order.
    /// - Returns: The scroll offset the follower should be set to, clamped to its valid range.
    public static func followerOffset(
        driverTop: Double,
        driverContentHeight: Double,
        driverViewportHeight: Double,
        driverHeadingYs: [Double],
        followerContentHeight: Double,
        followerViewportHeight: Double,
        followerHeadingYs: [Double]
    ) -> Double {
        let maxFollower = max(0, followerContentHeight - followerViewportHeight)

        // Build aligned pairs using min of both counts.
        let pairCount = min(driverHeadingYs.count, followerHeadingYs.count)

        // Proportional fallback helper.
        func proportional() -> Double {
            let maxDriver = driverContentHeight - driverViewportHeight
            let frac = maxDriver <= 0 ? 0.0 : clamp(driverTop / maxDriver, 0, 1)
            return frac * maxFollower
        }

        // Need at least 2 aligned pairs for heading-anchored interpolation.
        guard pairCount >= 2 else {
            return clamp(proportional(), 0, maxFollower)
        }

        let dYs = Array(driverHeadingYs.prefix(pairCount))
        let fYs = Array(followerHeadingYs.prefix(pairCount))

        // Before the first heading → proportional fallback.
        if driverTop < dYs[0] {
            return clamp(proportional(), 0, maxFollower)
        }

        // At or after the last heading → proportional fallback.
        if driverTop >= dYs[pairCount - 1] {
            return clamp(proportional(), 0, maxFollower)
        }

        // Find the greatest index i where dYs[i] <= driverTop and i+1 exists.
        var i = 0
        for idx in 0 ..< pairCount - 1 {
            if dYs[idx] <= driverTop {
                i = idx
            }
        }

        let segHeight = dYs[i + 1] - dYs[i]
        let f: Double
        if segHeight <= 0 {
            f = 0
        } else {
            f = clamp((driverTop - dYs[i]) / segHeight, 0, 1)
        }

        let result = fYs[i] + f * (fYs[i + 1] - fYs[i])
        return clamp(result, 0, maxFollower)
    }

    /// Clamps a scroll offset `y` to the valid scrollable range `[0, max(0, contentHeight - viewportHeight)]`.
    public static func clampOffset(_ y: Double, contentHeight: Double, viewportHeight: Double) -> Double {
        let maxY = max(0, contentHeight - viewportHeight)
        return clamp(y, 0, maxY)
    }

    // MARK: - Private helpers

    @inline(__always)
    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, value))
    }
}
