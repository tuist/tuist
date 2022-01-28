import Foundation
import TuistAsyncQueue
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported at https://backbone.tuist.io/
public struct TuistAnalyticsDispatcher: AsyncQueueDispatching {
    public static let dispatcherId = "TuistAnalytics"

    private let backends: [TuistAnalyticsBackend]

    public init(
        cloud: Cloud?,
        cloudClient: CloudClienting = CloudClient(),
        requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher()
    ) {
        let backbone = TuistAnalyticsBackboneBackend(requestDispatcher: requestDispatcher)
        if let cloud = cloud {
            backends = [
                backbone,
                TuistAnalyticsCloudBackend(
                    config: cloud,
                    resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: cloud),
                    client: cloudClient
                ),
            ]
        } else {
            backends = [backbone]
        }
    }

    // MARK: - AsyncQueueDispatching

    public var identifier = TuistAnalyticsDispatcher.dispatcherId

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () throws -> Void) throws {
        guard let commandEvent = event as? CommandEvent else { return }

        Task.detached {
            _ = try await backends.concurrentMap { try? await $0.send(commandEvent: commandEvent) }
            try completion()
        }
    }

    public func dispatchPersisted(data: Data, completion: @escaping () throws -> Void) throws {
        let decoder = JSONDecoder()
        let commandEvent = try decoder.decode(CommandEvent.self, from: data)
        return try dispatch(event: commandEvent, completion: completion)
    }
}
