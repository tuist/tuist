import Foundation
import TuistAsyncQueue

public final class TuistAnalytics {
    public static func bootstrap() {
        AsyncQueue.sharedInstance.register(dispatcher: TuistAnalyticsDispatcher())
        AsyncQueue.sharedInstance.start() // Re-try to send all events that got persisted and haven't been sent yet
    }
}
