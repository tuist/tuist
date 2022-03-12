import Foundation
import Queuer
import TuistCore
import TuistSupport

public protocol AsyncQueuing {
    /// It dispatches the given event.
    /// - Parameter event: Event to be dispatched.
    /// - Parameter didPersistEvent: It's called when the event has been persisted, to make sure it can't get lost
    func dispatch<T: AsyncQueueEvent>(event: T) throws
}

public class AsyncQueue: AsyncQueuing {
    // MARK: - Attributes

    private let queue: Queuing
    private let ciChecker: CIChecking
    private let persistor: AsyncQueuePersisting
    private var dispatchers: [String: AsyncQueueDispatching] = [:]

    public static let sharedInstance = AsyncQueue()

    // MARK: - Init

    init(
        queue: Queuing = Queuer.shared,
        ciChecker: CIChecking = CIChecker(),
        persistor: AsyncQueuePersisting = AsyncQueuePersistor()
    ) {
        self.queue = queue
        self.ciChecker = ciChecker
        self.persistor = persistor
    }

    public func register(dispatcher: AsyncQueueDispatching) {
        dispatchers[dispatcher.identifier] = dispatcher
    }

    // MARK: - AsyncQueuing

    public func start() {
        loadEvents()
        queue.resume()
    }

    public func dispatch<T: AsyncQueueEvent>(event: T) throws {
        guard let dispatcher = dispatchers[event.dispatcherId] else {
            logger.error("Couldn't find dispatcher with id: \(event.dispatcherId)")
            return
        }

        // We persist the event in case the dispatching is halted because Tuist's
        // process exits. In that case we want to retry again the next time there's
        // opportunity for that.
        try persistor.write(event: event)
        let operation = liveDispatchOperation(event: event, dispatcher: dispatcher)
        queue.addOperation(operation)
    }

    // MARK: - Private

    private func liveDispatchOperation<T: AsyncQueueEvent>(event: T, dispatcher: AsyncQueueDispatching) -> Operation {
        ConcurrentOperation(name: event.id.uuidString) { operation in
            logger.debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            do {
                try dispatcher.dispatch(event: event) {
                    try self.persistor.delete(event: event)
                    operation.success = true
                }
            } catch {
                operation.success = false
            }
        }
    }

    private func dispatchPersisted(eventTuple: AsyncQueueEventTuple) throws {
        guard let dispatcher = dispatchers.first(where: { $0.key == eventTuple.dispatcherId })?.value else {
            try deletePersistedEvent(filename: eventTuple.filename)
            logger.error("Couldn't find dispatcher for persisted event with id: \(eventTuple.dispatcherId)")
            return
        }

        let operation = persistedDispatchOperation(event: eventTuple, dispatcher: dispatcher)
        queue.addOperation(operation)
    }

    private func persistedDispatchOperation(
        event: AsyncQueueEventTuple,
        dispatcher: AsyncQueueDispatching
    ) -> Operation {
        ConcurrentOperation(name: event.id.uuidString) { _ in
            do {
                logger.debug("Dispatching persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
                try dispatcher.dispatchPersisted(data: event.data) {
                    try self.deletePersistedEvent(filename: event.filename)
                }
            } catch {
                logger.debug("Failed to dispatch persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            }
        }
    }

    private func waitIfCI() {
        if !ciChecker.isCI() { return }
        queue.waitUntilAllOperationsAreFinished()
    }

    private func loadEvents() {
        do {
            let events = try persistor.readAll()
            for event in events {
                try dispatchPersisted(eventTuple: event)
            }
        } catch {
            logger.debug("Error loading persisted events: \(error)")
        }
    }

    private func deletePersistedEvent(filename: String) throws {
        try persistor.delete(filename: filename)
    }
}
