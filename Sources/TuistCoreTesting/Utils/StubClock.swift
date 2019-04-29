import Foundation
import TuistCore

/// A stub clock that can be primed with
/// multiple dates and timers.
public class StubClock: Clock {
    /// Returns primed dates in the order they
    /// were added to `primedDates`.
    ///
    /// In the event there are no primed dates, `Date.distantPast`
    /// is returned.
    public var now: Date {
        if let first = primedDates.first {
            primedDates.removeFirst()
            return first
        }
        return .distantPast
    }

    public var primedDates: [Date] = []
    public var primedTimers: [TimeInterval] = []

    public init() {}

    /// Returns stub timers that are primed with time intervals in the
    /// the order they were defined in `primedTimers`.
    ///
    /// In the event there are no primed time intervals, A stub timer
    /// with a time interval of `0` is returned.
    public func startTimer() -> ClockTimer {
        if let first = primedTimers.first {
            primedTimers.removeFirst()
            return Timer(timeInterval: first)
        }
        return Timer(timeInterval: 0.0)
    }

    private class Timer: ClockTimer {
        private let timeInterval: TimeInterval
        fileprivate init(timeInterval: TimeInterval) {
            self.timeInterval = timeInterval
        }

        func stop() -> TimeInterval {
            return timeInterval
        }
    }
}
