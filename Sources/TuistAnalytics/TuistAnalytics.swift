import Foundation
import TSCBasic
import TuistAsyncQueue
import TuistGraph
import TuistLoader

public enum TuistAnalytics {
    public static func bootstrap(config: Config) throws {
        AsyncQueue.sharedInstance.register(dispatcher: TuistAnalyticsDispatcher(cloud: config.cloud))
        AsyncQueue.sharedInstance.start() // Re-try to send all events that got persisted and haven't been sent yet
    }
}
