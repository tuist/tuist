import Foundation
import TSCBasic
import TuistAsyncQueue
import TuistGraph
import TuistLoader

public final class TuistAnalytics {
    public static func bootstrap(configLoader: ConfigLoader = ConfigLoader(manifestLoader: ManifestLoader())) throws {
        let path: AbsolutePath
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--path") {
            path = AbsolutePath(CommandLine.arguments[argumentIndex + 1], relativeTo: .current)
        } else {
            path = .current
        }

        AsyncQueue.sharedInstance.register(dispatcher: TuistAnalyticsDispatcher(cloud: try configLoader.loadConfig(path: path).cloud))
        AsyncQueue.sharedInstance.start() // Re-try to send all events that got persisted and haven't been sent yet
    }
}
