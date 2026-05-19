import Foundation

/// Deterministic self-tests for live-reload primitives.
/// All assertions use `DebounceState` — no wall-clock sleeps.
public func liveReloadCases() -> [TestCase] {
    [
        TestCase("liveReload/debounce-empty-sequence") { t in
            let state = DebounceState(interval: 0.3)
            let fired = state.firingTimestamps(from: [])
            t.expectEqual(fired.count, 0, "empty input should produce no firings")
        },

        TestCase("liveReload/debounce-single-event-fires") { t in
            let state = DebounceState(interval: 0.3)
            let fired = state.firingTimestamps(from: [0.0])
            t.expectEqual(fired.count, 1, "a single event must fire")
            t.expectEqual(fired.first ?? -1, 0.0, "fired timestamp must match input")
        },

        TestCase("liveReload/debounce-burst-collapses-to-one") { t in
            // Five events within 0.1 s of each other → only the last fires.
            let state = DebounceState(interval: 0.3)
            let burst: [TimeInterval] = [0.0, 0.05, 0.10, 0.15, 0.20]
            let fired = state.firingTimestamps(from: burst)
            t.expectEqual(fired.count, 1, "rapid burst must collapse to one firing")
            t.expectEqual(fired.first ?? -1, 0.20, "last timestamp in burst must fire")
        },

        TestCase("liveReload/debounce-two-separate-bursts-fire-twice") { t in
            // Burst 1: 0.0–0.1 s; gap; Burst 2: 1.0–1.1 s.
            let state = DebounceState(interval: 0.3)
            let timestamps: [TimeInterval] = [0.0, 0.05, 0.10, 1.00, 1.05, 1.10]
            let fired = state.firingTimestamps(from: timestamps)
            t.expectEqual(fired.count, 2, "two separate bursts must produce two firings")
            t.expectEqual(fired[0], 0.10, "first burst last timestamp")
            t.expectEqual(fired[1], 1.10, "second burst last timestamp")
        },

        TestCase("liveReload/debounce-events-exactly-at-interval-boundary") { t in
            // Events spaced exactly `interval` apart are NOT within the interval,
            // so each one fires independently.
            let state = DebounceState(interval: 0.3)
            let timestamps: [TimeInterval] = [0.0, 0.3, 0.6]
            let fired = state.firingTimestamps(from: timestamps)
            t.expectEqual(fired.count, 3, "events at exact interval boundary each fire")
        },

        TestCase("liveReload/debounce-events-just-inside-interval-collapse") { t in
            let state = DebounceState(interval: 0.3)
            // 0.29 < 0.3: still within interval → only last fires
            let timestamps: [TimeInterval] = [0.0, 0.29]
            let fired = state.firingTimestamps(from: timestamps)
            t.expectEqual(fired.count, 1, "events just inside interval must collapse")
            t.expectEqual(fired.first ?? -1, 0.29)
        },

        TestCase("liveReload/debounceState-interval-stored") { t in
            let state = DebounceState(interval: 0.5)
            t.expectEqual(state.interval, 0.5, "interval property must be stored correctly")
        }
    ]
}
