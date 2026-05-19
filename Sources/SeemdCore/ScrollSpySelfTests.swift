import Foundation

/// Self-test cases for `ScrollSpy.activeSlug` (US-008).
public func scrollSpyCases() -> [TestCase] {
    [
        TestCase("scrollSpy/empty-returns-nil") { t in
            let result = ScrollSpy.activeSlug(headingFrames: [])
            t.expect(result == nil, "empty frames should return nil, got \(String(describing: result))")
        },

        TestCase("scrollSpy/at-top-all-below-inset-returns-first") { t in
            // All headings below the top (positive minY) → first slug highlighted.
            let frames = [
                HeadingFrame(slug: "intro", minY: 50),
                HeadingFrame(slug: "background", minY: 200),
                HeadingFrame(slug: "conclusion", minY: 400),
            ]
            let result = ScrollSpy.activeSlug(headingFrames: frames)
            t.expectEqual(result, "intro", "all headings below viewport top → first slug")
        },

        TestCase("scrollSpy/scrolled-to-heading-b") { t in
            // Heading A is above the top (negative minY), B is at/above the top,
            // C is still below → active should be B.
            let frames = [
                HeadingFrame(slug: "alpha", minY: -150),
                HeadingFrame(slug: "beta", minY: -5),
                HeadingFrame(slug: "gamma", minY: 80),
            ]
            let result = ScrollSpy.activeSlug(headingFrames: frames)
            t.expectEqual(result, "beta", "last heading at/above top edge should be active")
        },

        TestCase("scrollSpy/scrolled-past-last-heading-returns-last") { t in
            // All headings scrolled above the top → last in document order is active.
            let frames = [
                HeadingFrame(slug: "one", minY: -500),
                HeadingFrame(slug: "two", minY: -300),
                HeadingFrame(slug: "three", minY: -50),
            ]
            let result = ScrollSpy.activeSlug(headingFrames: frames)
            t.expectEqual(result, "three", "all above → last document-order heading active")
        },

        TestCase("scrollSpy/exact-boundary-counts-as-active") { t in
            // A heading whose minY exactly equals viewportTopInset is active.
            let frames = [
                HeadingFrame(slug: "section-a", minY: -100),
                HeadingFrame(slug: "section-b", minY: 0),   // exactly at inset
                HeadingFrame(slug: "section-c", minY: 80),
            ]
            let result = ScrollSpy.activeSlug(headingFrames: frames)
            t.expectEqual(result, "section-b", "minY == inset (0) should count as active")
        },

        TestCase("scrollSpy/custom-nonzero-inset") { t in
            // With a positive inset (e.g. 12-pt threshold), any heading with
            // minY <= 12 is considered at/above the top.
            let frames = [
                HeadingFrame(slug: "h1", minY: -200),
                HeadingFrame(slug: "h2", minY: 8),    // 8 <= 12, so at/above
                HeadingFrame(slug: "h3", minY: 50),   // 50 > 12, below
            ]
            let result = ScrollSpy.activeSlug(headingFrames: frames, viewportTopInset: 12)
            t.expectEqual(result, "h2", "custom inset=12: h2 (minY=8) should be active")
        },
    ]
}
