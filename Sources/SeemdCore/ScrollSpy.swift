import Foundation

/// A heading's vertical position relative to the scroll viewport's top edge.
///
/// `minY` is the heading's top-edge Y offset in the scroll coordinate space;
/// negative values mean the heading has scrolled above the viewport top.
public struct HeadingFrame: Equatable {
    public let slug: String
    public let minY: Double

    public init(slug: String, minY: Double) {
        self.slug = slug
        self.minY = minY
    }
}

/// Pure scroll-spy logic: maps a list of heading frames to the active slug.
public enum ScrollSpy {
    /// Returns the slug of the active heading given the current frame snapshot.
    ///
    /// The active heading is the LAST one (in document order) whose `minY` is
    /// at or below `viewportTopInset` — i.e. the deepest heading whose top edge
    /// is at or above the viewport's top, indicating the section currently in
    /// view.
    ///
    /// - If no heading satisfies that condition (all are below the top, as when
    ///   the reader is at the very top before any heading), the FIRST heading's
    ///   slug is returned so the first TOC item stays highlighted.
    /// - Returns `nil` only when `headingFrames` is empty.
    /// - Input order is treated as document order; frames need not be pre-sorted.
    public static func activeSlug(
        headingFrames: [HeadingFrame],
        viewportTopInset: Double = 0
    ) -> String? {
        guard !headingFrames.isEmpty else { return nil }

        // Walk in document order, collecting all headings at/above the inset.
        var candidate: String? = nil
        for frame in headingFrames {
            if frame.minY <= viewportTopInset {
                candidate = frame.slug
            }
        }

        // If no heading is at/above the inset, fall back to the first heading.
        return candidate ?? headingFrames[0].slug
    }
}
