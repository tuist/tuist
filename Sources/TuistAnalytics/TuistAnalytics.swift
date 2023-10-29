import Foundation
import TSCBasic
import TuistAsyncQueue
import TuistGraph
import TuistLoader

public enum TuistAnalytics {
    public static func bootstrap(dispatcher: TuistAnalyticsDispatcher) throws {
        AsyncQueue.sharedInstance.register(dispatcher: dispatcher)
        Task.detached(priority: .background) {
            AsyncQueue.sharedInstance.start() // Re-try to send all events that got persisted and haven't been sent yet
        }
    }
}
