import Foundation

public protocol ClockTimer {
    func stop() -> TimeInterval
}

public protocol Clock {
    var now: Date { get }
    func startTimer() -> ClockTimer
}

public class WallClock: Clock {
    public var now: Date {
        return Date()
    }

    public init() {}

    public func startTimer() -> ClockTimer {
        return Timer(clock: self)
    }

    private class Timer: ClockTimer {
        private let start: Date
        private let clock: Clock

        fileprivate init(clock: Clock) {
            self.clock = clock
            start = clock.now
        }

        func stop() -> TimeInterval {
            return clock.now.timeIntervalSince(start)
        }
    }
}
