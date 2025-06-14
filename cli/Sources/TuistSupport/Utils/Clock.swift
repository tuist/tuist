import Foundation

/// A clock can be used to obtain the current date
/// as well as create `ClockTimers` to measure
/// time intervals between events.
public protocol Clock {
    var now: Date { get }
    func startTimer() -> ClockTimer
}

/// A clock timer can be used to measure
/// time intervals between events
///
/// A timer can be obtained from a `Clock`
/// by calling `startTimer()`. Calling
/// `stop()` on the timer will return
/// the time interval since the start.
public protocol ClockTimer {
    func stop() -> TimeInterval
}

/// A wall clock is the default implementation of
/// the `Clock` interface
public class WallClock: Clock {
    public var now: Date {
        Date()
    }

    public init() {}

    public func startTimer() -> ClockTimer {
        Timer(clock: self)
    }

    private class Timer: ClockTimer {
        private let start: Date
        private let clock: Clock

        fileprivate init(clock: Clock) {
            self.clock = clock
            start = clock.now
        }

        func stop() -> TimeInterval {
            clock.now.timeIntervalSince(start)
        }
    }
}
