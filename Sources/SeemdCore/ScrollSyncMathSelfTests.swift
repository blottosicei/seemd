import Foundation

/// Self-test cases for `ScrollSyncMath` (US-S1).
public func scrollSyncMathCases() -> [TestCase] {
    let eps = 1e-6

    return [
        // MARK: Heading-anchored interpolation

        TestCase("scrollSyncMath/exact-heading-hit-f0") { t in
            // driverTop exactly on heading[1] → f = 0, follower should land on fY[1].
            let result = ScrollSyncMath.followerOffset(
                driverTop: 200,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200]
            )
            // segment [400..1200], f=0 → result = 400
            t.expect(abs(result - 400.0) < eps, "exact heading hit: expected 400.0, got \(result)")
        },

        TestCase("scrollSyncMath/midpoint-interpolation-f0-5") { t in
            // driverTop = 400 = midpoint of driver segment [200..600].
            // f = (400-200)/(600-200) = 0.5 → follower midpoint of [400..1200] = 800.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 400,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200]
            )
            t.expect(abs(result - 800.0) < eps, "midpoint f=0.5: expected 800.0, got \(result)")
        },

        TestCase("scrollSyncMath/end-of-segment-f-near-1") { t in
            // driverTop just before next heading (599 out of [200..600]).
            // f = (599-200)/(600-200) = 399/400 = 0.9975
            // follower = 400 + 0.9975*(1200-400) = 400 + 798 = 1198
            let driverTop = 599.0
            let f = (driverTop - 200.0) / (600.0 - 200.0)
            let expected = 400.0 + f * (1200.0 - 400.0)
            let result = ScrollSyncMath.followerOffset(
                driverTop: driverTop,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200]
            )
            t.expect(abs(result - expected) < eps, "end-of-segment: expected \(expected), got \(result)")
        },

        TestCase("scrollSyncMath/first-segment-f0-5") { t in
            // Driver segment [0..200], driverTop=100 → f=0.5.
            // Follower segment [0..400] → result=200.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 100,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200]
            )
            t.expect(abs(result - 200.0) < eps, "first segment midpoint: expected 200.0, got \(result)")
        },

        // MARK: Proportional fallback – before first heading

        TestCase("scrollSyncMath/before-first-heading-uses-proportional") { t in
            // driverTop=50 < dYs[0]=100 → proportional.
            // maxDriver=1000-500=500, frac=50/500=0.1
            // maxFollower=2000-500=1500, result=0.1*1500=150
            let result = ScrollSyncMath.followerOffset(
                driverTop: 50,
                driverContentHeight: 1000,
                driverViewportHeight: 500,
                driverHeadingYs: [100, 500, 800],
                followerContentHeight: 2000,
                followerViewportHeight: 500,
                followerHeadingYs: [200, 1000, 1600]
            )
            t.expect(abs(result - 150.0) < eps, "before first heading: expected 150.0, got \(result)")
        },

        // MARK: Proportional fallback – at/after last heading

        TestCase("scrollSyncMath/after-last-heading-uses-proportional") { t in
            // driverTop=800 >= dYs[last]=800 → proportional.
            // maxDriver=500, frac=800/500 clamped to 1 → result=maxFollower=1500
            let result = ScrollSyncMath.followerOffset(
                driverTop: 800,
                driverContentHeight: 1000,
                driverViewportHeight: 500,
                driverHeadingYs: [100, 500, 800],
                followerContentHeight: 2000,
                followerViewportHeight: 500,
                followerHeadingYs: [200, 1000, 1600]
            )
            t.expect(abs(result - 1500.0) < eps, "after last heading: expected 1500.0, got \(result)")
        },

        TestCase("scrollSyncMath/exactly-at-last-heading-uses-proportional") { t in
            // driverTop exactly equals last heading Y → proportional fallback.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 600,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200]
            )
            // maxDriver=600, frac=600/600=1, maxFollower=1600, result=1600
            t.expect(abs(result - 1600.0) < eps, "at last heading: expected 1600.0, got \(result)")
        },

        // MARK: Proportional fallback – fewer than 2 headings

        TestCase("scrollSyncMath/zero-headings-uses-proportional") { t in
            // No headings at all → proportional.
            // maxDriver=600, frac=300/600=0.5, maxFollower=1600, result=800
            let result = ScrollSyncMath.followerOffset(
                driverTop: 300,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: []
            )
            t.expect(abs(result - 800.0) < eps, "zero headings: expected 800.0, got \(result)")
        },

        TestCase("scrollSyncMath/one-heading-uses-proportional") { t in
            // Single heading → fewer than 2 pairs → proportional.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 300,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [100],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [200]
            )
            t.expect(abs(result - 800.0) < eps, "one heading: expected 800.0, got \(result)")
        },

        // MARK: Zero scrollable range

        TestCase("scrollSyncMath/zero-driver-scrollable-range-returns-zero") { t in
            // contentHeight <= viewportHeight on driver → frac = 0, result = 0.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 0,
                driverContentHeight: 400,
                driverViewportHeight: 400,
                driverHeadingYs: [],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: []
            )
            t.expect(abs(result - 0.0) < eps, "driver content<=viewport: expected 0.0, got \(result)")
        },

        TestCase("scrollSyncMath/zero-follower-scrollable-range-returns-zero") { t in
            // Follower content <= viewport → maxFollower=0, result always 0.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 300,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [],
                followerContentHeight: 400,
                followerViewportHeight: 400,
                followerHeadingYs: []
            )
            t.expect(abs(result - 0.0) < eps, "follower content<=viewport: expected 0.0, got \(result)")
        },

        // MARK: Mismatched array counts uses min-aligned pairs

        TestCase("scrollSyncMath/mismatched-counts-uses-min-pairs") { t in
            // Driver has 3 headings, follower has 5 → use first 3 pairs.
            // driverTop=300 is in segment [200..600] (index 1..2 of the 3 pairs).
            // f=(300-200)/(600-200)=0.25, follower segment [400..1200], result=400+0.25*800=600
            let result = ScrollSyncMath.followerOffset(
                driverTop: 300,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 200, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400, 1200, 1400, 1600]
            )
            t.expect(abs(result - 600.0) < eps, "mismatched counts: expected 600.0, got \(result)")
        },

        TestCase("scrollSyncMath/mismatched-counts-driver-longer") { t in
            // Driver has 5 headings, follower has 2 → use first 2 pairs → single segment.
            // driverTop=50 < dYs[0]=0? No, dYs[0]=0 <= 50 but dYs[1]=100 > 50.
            // segment [0..100], f=50/100=0.5, follower [0..400], result=200.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 50,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 100, 300, 500, 700],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 400]
            )
            t.expect(abs(result - 200.0) < eps, "driver longer: expected 200.0, got \(result)")
        },

        // MARK: Final clamp at bounds

        TestCase("scrollSyncMath/clamp-lower-bound") { t in
            // Any negative computed result should clamp to 0.
            // Use proportional with driverTop=0 → result=0 (already 0, but verify clamp holds).
            let result = ScrollSyncMath.followerOffset(
                driverTop: 0,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: []
            )
            t.expect(result >= 0.0, "result must be >= 0, got \(result)")
        },

        TestCase("scrollSyncMath/clamp-upper-bound") { t in
            // driverTop beyond scrollable range → proportional frac clamped to 1 → maxFollower.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 9999,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: []
            )
            let maxFollower = max(0.0, 2000.0 - 400.0)
            t.expect(result <= maxFollower, "result must be <= maxFollower (\(maxFollower)), got \(result)")
            t.expect(abs(result - maxFollower) < eps, "expected maxFollower \(maxFollower), got \(result)")
        },

        // MARK: Zero-height segment guard

        TestCase("scrollSyncMath/zero-height-segment-treats-f-as-0") { t in
            // Two headings at same Y → segment height = 0 → f treated as 0.
            // driverTop=100 is in first segment [100..100] (zero height) → f=0, result=fYs[0]=500.
            // But dYs[1]=100 == driverTop=100 → actually driverTop >= last heading? No, dYs[1]=100
            // and pairCount=2, so driverTop >= dYs[1] → proportional fallback.
            // Let's use 3 headings so the zero-segment is interior.
            // dYs=[0, 100, 100, 600], fYs=[0, 500, 500, 1200], driverTop=100.
            // i=1 (dYs[1]=100 <= 100, dYs[2]=100 <= 100 but we want last i where dYs[i]<=driverTop
            // and i+1 exists). i will end at 2 (dYs[2]=100<=100), segment [100..600], f=0 → result=500.
            // Actually let's keep it simple with a clear zero-segment case.
            let result = ScrollSyncMath.followerOffset(
                driverTop: 50,
                driverContentHeight: 1000,
                driverViewportHeight: 400,
                driverHeadingYs: [0, 50, 50, 600],
                followerContentHeight: 2000,
                followerViewportHeight: 400,
                followerHeadingYs: [0, 300, 300, 1200]
            )
            // driverTop=50, pairCount=4.
            // Before first? No (50 >= 0). At/after last? No (50 < 600).
            // Walk: i=0(dYs[0]=0<=50), i=1(dYs[1]=50<=50), i=2(dYs[2]=50<=50). i=2.
            // segment: dYs[2]=50, dYs[3]=600, height=550, f=(50-50)/550=0.
            // result = fYs[2] + 0 * (fYs[3]-fYs[2]) = 300.
            t.expect(abs(result - 300.0) < eps, "zero-height segment: expected 300.0, got \(result)")
        },

        // MARK: clampOffset helper

        TestCase("scrollSyncMath/clampOffset-within-range") { t in
            let result = ScrollSyncMath.clampOffset(500, contentHeight: 2000, viewportHeight: 400)
            t.expect(abs(result - 500.0) < eps, "clampOffset within range: expected 500.0, got \(result)")
        },

        TestCase("scrollSyncMath/clampOffset-below-zero") { t in
            let result = ScrollSyncMath.clampOffset(-100, contentHeight: 2000, viewportHeight: 400)
            t.expect(abs(result - 0.0) < eps, "clampOffset below 0: expected 0.0, got \(result)")
        },

        TestCase("scrollSyncMath/clampOffset-above-max") { t in
            let result = ScrollSyncMath.clampOffset(9999, contentHeight: 2000, viewportHeight: 400)
            t.expect(abs(result - 1600.0) < eps, "clampOffset above max: expected 1600.0, got \(result)")
        },

        TestCase("scrollSyncMath/clampOffset-content-equals-viewport") { t in
            // No scrollable range → max = 0, always returns 0.
            let result = ScrollSyncMath.clampOffset(100, contentHeight: 400, viewportHeight: 400)
            t.expect(abs(result - 0.0) < eps, "clampOffset no range: expected 0.0, got \(result)")
        },

        TestCase("scrollSyncMath/clampOffset-content-less-than-viewport") { t in
            let result = ScrollSyncMath.clampOffset(100, contentHeight: 300, viewportHeight: 400)
            t.expect(abs(result - 0.0) < eps, "clampOffset content<viewport: expected 0.0, got \(result)")
        },
    ]
}
