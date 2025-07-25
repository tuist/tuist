import Foundation
import TuistCore
import TuistServer
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
            // The queue dependency that we use uses Dispatch and Operations, which don't propagate the task local states.
            // Since analytics dispatcher is something we run only in the CLI, we can assume background refresh.
            try await ServerAuthenticationConfig.$current.withValue(ServerAuthenticationConfig(backgroundRefresh: true)) {
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
