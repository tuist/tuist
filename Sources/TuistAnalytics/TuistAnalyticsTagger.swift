import Foundation

public protocol TuistAnalyticsTagging {
    func tag(commandEvent: CommandEvent)
}

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported at https://stats.tuist.io/
public struct TuistAnalyticsTagger: TuistAnalyticsTagging {
    public init() {}

    // MARK: - TuistAnalyticsTagging

    /// Send analytics regarding the execution of a command, represented by `commandEvent`
    public func tag(commandEvent _: CommandEvent) {
        // TODO: implement tag
    }
}
