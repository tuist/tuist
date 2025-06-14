import Foundation

public protocol TimeTakenLoggerFormatting {
    func timeTakenMessage(for timer: ClockTimer) -> Logger.Message
}

public class TimeTakenLoggerFormatter: TimeTakenLoggerFormatting {
    public init() {}

    public func timeTakenMessage(for timer: ClockTimer) -> Logger.Message {
        let time = String(format: "%.3f", timer.stop())
        return "Total time taken: \(time)s"
    }
}
