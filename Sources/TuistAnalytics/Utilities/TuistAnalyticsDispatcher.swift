import Foundation
import TuistAsyncQueue
#if canImport(TuistCloud)
    import TuistCloud
#endif
import TuistCore
import TuistGraph
import TuistSupport

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported to the cloud backend (if defined)
public struct TuistAnalyticsDispatcher: AsyncQueueDispatching {
    public static let dispatcherId = "TuistAnalytics"

    private let backend: TuistAnalyticsBackend?

    private init(backend: TuistAnalyticsBackend?) {
        self.backend = backend
    }

    #if canImport(TuistCloud)
        public init(cloud: Cloud?, cloudClient: CloudClienting? = CloudClient()) {
            if let cloud, let cloudClient {
                let backend = TuistAnalyticsCloudBackend(
                    config: cloud,
                    resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: cloud),
                    client: cloudClient
                )
                self.init(backend: backend)
            } else {
                self.init(backend: nil)
            }
        }
    #else
        public init(cloud _: Cloud?) {
            self.init(backend: nil)
        }
    #endif

    // MARK: - AsyncQueueDispatching

    public var identifier = TuistAnalyticsDispatcher.dispatcherId

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () throws -> Void) throws {
        guard let commandEvent = event as? CommandEvent else { return }

        Task.detached {
            _ = try? await backend?.send(commandEvent: commandEvent)
            try completion()
        }
    }

    public func dispatchPersisted(data: Data, completion: @escaping () throws -> Void) throws {
        let decoder = JSONDecoder()
        let commandEvent = try decoder.decode(CommandEvent.self, from: data)
        return try dispatch(event: commandEvent, completion: completion)
    }
}
