import Foundation

/// Self-test cases for SearchEngine and ZoomScale (US-009).
/// Wire into seemd-selftest/main.swift by appending `searchZoomCases()`.
public func searchZoomCases() -> [TestCase] {
    [
        // MARK: SearchEngine — basic match
        TestCase("search/case-insensitive-match") { t in
            let ranges = SearchEngine.matches(in: "Hello World hello", query: "hello")
            t.expectEqual(ranges.count, 2, "should find 2 case-insensitive matches")
        },

        TestCase("search/match-count-convenience") { t in
            let count = SearchEngine.matchCount(in: "Swift swift SWIFT", query: "swift")
            t.expectEqual(count, 3, "matchCount should return 3")
        },

        TestCase("search/empty-query-returns-empty") { t in
            let ranges = SearchEngine.matches(in: "any text here", query: "")
            t.expectEqual(ranges.count, 0, "empty query must return []")
        },

        TestCase("search/no-match-returns-empty") { t in
            let ranges = SearchEngine.matches(in: "hello world", query: "xyz")
            t.expectEqual(ranges.count, 0, "no-match query must return []")
        },

        TestCase("search/non-overlapping-ranges") { t in
            // "aaa" with query "aa" should give exactly 1 non-overlapping match
            let ranges = SearchEngine.matches(in: "aaa", query: "aa")
            t.expectEqual(ranges.count, 1, "non-overlapping: 'aa' in 'aaa' = 1 match")
        },

        TestCase("search/match-range-values") { t in
            let text = "abcABC"
            let ranges = SearchEngine.matches(in: text, query: "abc")
            t.expectEqual(ranges.count, 2, "should match 'abc' and 'ABC'")
            // Verify the substring captured by each range
            let first = String(text[ranges[0]])
            let second = String(text[ranges[1]])
            t.expect(first.lowercased() == "abc", "first match should be 'abc' (got \(first))")
            t.expect(second.lowercased() == "abc", "second match should be 'ABC' (got \(second))")
        },

        // MARK: ZoomScale — clamp
        TestCase("zoom/clamp-within-bounds") { t in
            t.expectEqual(ZoomScale.clamp(1.5), 1.5)
        },

        TestCase("zoom/clamp-at-min") { t in
            t.expectEqual(ZoomScale.clamp(0.0), ZoomScale.min, "below min -> min")
        },

        TestCase("zoom/clamp-at-max") { t in
            t.expectEqual(ZoomScale.clamp(5.0), ZoomScale.max, "above max -> max")
        },

        // MARK: ZoomScale — step
        TestCase("zoom/zoom-in-step") { t in
            let result = ZoomScale.zoomIn(1.0)
            t.expectEqual(result, 1.1, "1.0 + 0.1 step = 1.1")
        },

        TestCase("zoom/zoom-out-step") { t in
            let result = ZoomScale.zoomOut(1.0)
            // Use rounding to avoid floating-point noise
            let rounded = (result * 10).rounded() / 10
            t.expectEqual(rounded, 0.9, "1.0 - 0.1 step = 0.9")
        },

        TestCase("zoom/zoom-in-clamps-at-max") { t in
            let result = ZoomScale.zoomIn(3.0)
            t.expectEqual(result, ZoomScale.max, "zoom in at max stays at max")
        },

        TestCase("zoom/zoom-out-clamps-at-min") { t in
            let result = ZoomScale.zoomOut(0.5)
            t.expectEqual(result, ZoomScale.min, "zoom out at min stays at min")
        },

        TestCase("zoom/reset-returns-default") { t in
            t.expectEqual(ZoomScale.reset(), ZoomScale.default, "reset() == 1.0")
        },

        // MARK: ZoomScale — persistence
        TestCase("zoom/persistence-round-trip") { t in
            let suiteName = "seemd.test.zoom.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "failed to create in-memory UserDefaults")
                return
            }
            ZoomScale.save(2.0, to: ud)
            let loaded = ZoomScale.load(from: ud)
            t.expectEqual(loaded, 2.0, "round-trip: save 2.0 -> load 2.0")
            // Clean up
            ud.removePersistentDomain(forName: suiteName)
        },

        TestCase("zoom/persistence-absent-returns-default") { t in
            let suiteName = "seemd.test.zoom.absent.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "failed to create in-memory UserDefaults")
                return
            }
            let loaded = ZoomScale.load(from: ud)
            t.expectEqual(loaded, ZoomScale.default, "absent key -> default 1.0")
            ud.removePersistentDomain(forName: suiteName)
        },

        TestCase("zoom/persistence-clamps-stored-value") { t in
            let suiteName = "seemd.test.zoom.clamp.\(UUID().uuidString)"
            guard let ud = UserDefaults(suiteName: suiteName) else {
                t.expect(false, "failed to create in-memory UserDefaults")
                return
            }
            // Save a value that is already above the 3.0 max to confirm save clamps
            ZoomScale.save(10.0, to: ud)
            let loaded = ZoomScale.load(from: ud)
            t.expectEqual(loaded, ZoomScale.max, "value > max clamped to max on save")
            ud.removePersistentDomain(forName: suiteName)
        },
    ]
}
