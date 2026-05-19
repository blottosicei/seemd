import Foundation

// MARK: - Pure coalescing logic (deterministically testable)

/// Pure value type that computes which timestamps in a sequence would actually
/// fire given a debounce interval.  No wall-clock dependency — pass any
/// sequence of `TimeInterval` values (e.g. 0, 0.1, 0.5 …) and the interval.
///
/// Rule: an event at index `i` fires if and only if there is no subsequent
/// event within `interval` seconds of it (i.e. it is the last in its burst).
public struct DebounceState {
    public let interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// Returns the subset of `timestamps` that would fire.
    /// `timestamps` must be non-decreasing.
    public func firingTimestamps(from timestamps: [TimeInterval]) -> [TimeInterval] {
        guard !timestamps.isEmpty else { return [] }
        var result: [TimeInterval] = []
        for (i, ts) in timestamps.enumerated() {
            let isLast = i == timestamps.count - 1
            let nextTooClose = !isLast && (timestamps[i + 1] - ts) < interval
            if !nextTooClose {
                result.append(ts)
            }
        }
        return result
    }
}

// MARK: - Real-time debouncer

/// Coalesces rapid calls to `schedule(_:)` so that only the last closure fires
/// after `interval` seconds of quiescence on `queue`.
public final class Debouncer {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?

    public init(interval: TimeInterval, queue: DispatchQueue = .main) {
        self.interval = interval
        self.queue = queue
    }

    /// Schedule `work` to run after the debounce interval.
    /// Calling this again before the interval elapses cancels the previous schedule.
    public func schedule(_ work: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: work)
        workItem = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    /// Cancel any pending scheduled work without executing it.
    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
