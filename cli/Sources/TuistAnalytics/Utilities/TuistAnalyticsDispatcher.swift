import Foundation
import TuistCore
import TuistSupport

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported to the Tuist server (if defined)
public struct TuistAnalyticsDispatcher: AsyncQueueDispatching {
    public static let dispatcherId = "TuistAnalytics"

    private let backend: TuistAnalyticsBackend

    public init(backend: TuistAnalyticsBackend) {
        self.backend = backend
    }

    // MARK: - AsyncQueueDispatching

    public var identifier = TuistAnalyticsDispatcher.dispatcherId

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () async throws -> Void) throws {
        guard let commandEvent = event as? CommandEvent else { return }
        Task {
            // The queuing library that we use under the hood, [Queuer](https://github.com/FabrizioBrancati/Queuer),
            // uses OperationQueue and Dispatch, which doesn't propagate task locals. Since this utility is only
            // run in the context of the CLI, we can assume CLI and force the product here.
            var environment = Environment.current
            environment.product = .cli
            try await Environment.$current.withValue(environment) {
                _ = try? await backend.send(commandEvent: commandEvent)
                try await completion()
            }
        }
    }

    public func dispatchPersisted(data: Data, completion: @escaping () async throws -> Void) throws {
        let decoder = JSONDecoder()
        let commandEvent = try decoder.decode(CommandEvent.self, from: data)
        return try dispatch(event: commandEvent, completion: completion)
    }
}
