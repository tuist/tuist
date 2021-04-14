import Foundation
import TuistSupport
import XCTest

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

    /// The dates to return when calling `now`
    /// in the order they are specified.
    public var primedDates: [Date] = []

    /// The time intervals to return from timers
    /// obtained when calling `startTimer()` in the
    /// order they are specified.
    public var primedTimers: [TimeInterval] = []

    /// Asserts when the stub methods are called
    /// while there is no more stubbed data
    public var assertOnUnexpectedCalls: Bool = false

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
        if assertOnUnexpectedCalls {
            XCTFail("Trying to get more timers than the ones stubbed")
        }
        return Timer(timeInterval: 0.0)
    }

    private class Timer: ClockTimer {
        private let timeInterval: TimeInterval
        private var stopCount = 0
        fileprivate init(timeInterval: TimeInterval) {
            self.timeInterval = timeInterval
        }

        func stop() -> TimeInterval {
            defer {
                stopCount += 1
            }

            if stopCount >= 1 {
                XCTFail("Attempting to stop a timer more than once")
            }

            return timeInterval
        }
    }
}
