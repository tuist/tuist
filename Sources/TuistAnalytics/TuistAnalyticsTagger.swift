import Foundation

public protocol TuistAnalyticsTagging {
    func tag(commandEvent: CommandEvent)
}

public struct TuistAnalyticsTagger: TuistAnalyticsTagging {
    public func tag(commandEvent _: CommandEvent) {
        // ...
    }
}
