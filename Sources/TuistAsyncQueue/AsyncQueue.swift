import Foundation
import Mockable
import Queuer
import TuistCore
import TuistSupport

@Mockable
public protocol AsyncQueuing {
    /// It dispatches the given event.
    /// - Parameter event: Event to be dispatched.
    /// - Parameter didPersistEvent: It's called when the event has been persisted, to make sure it can't get lost
    func dispatch<T: AsyncQueueEvent>(event: T) throws

    /// Waits for the queue to be fulfilled if on the CI
    func waitIfCI()

    /// Waits for the queue to be fulfilled
    func wait()
}

private final class AsyncConcurrentOperation: ConcurrentOperation, @unchecked Sendable {
    /// We want to have control over when `finish` is called
    /// Otherwise, `finish` is called immediately and it doesn't wait for the full completion of an async operation
    override func execute() {
        if let executionBlock {
            executionBlock(self)
        }
    }
}

public class AsyncQueue: AsyncQueuing {
    // MARK: - Attributes

    private let queue: Queuing
    private let persistor: AsyncQueuePersisting
    private var dispatchers: [String: AsyncQueueDispatching] = [:]

    public static let sharedInstance = AsyncQueue()

    // MARK: - Init

    init(
        queue: Queuing = Queuer.shared,
        persistor: AsyncQueuePersisting = AsyncQueuePersistor()
    ) {
        self.queue = queue
        self.persistor = persistor
    }

    public func register(dispatcher: AsyncQueueDispatching) {
        dispatchers[dispatcher.identifier] = dispatcher
    }

    // MARK: - AsyncQueuing

    public func start() async {
        await loadEvents()
        queue.resume()
        waitIfCI()
    }

    public func waitIfCI() {
        if !Environment.current.isCI { return }
        wait()
    }

    public func wait() {
        queue.waitUntilAllOperationsAreFinished()
    }

    public func dispatch(event: some AsyncQueueEvent) throws {
        guard let dispatcher = dispatchers[event.dispatcherId] else {
            Logger.current
                .debug("Couldn't find dispatcher with id: \(event.dispatcherId), skipping dispatching \(event.id)")
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

    private func liveDispatchOperation(event: some AsyncQueueEvent, dispatcher: AsyncQueueDispatching) -> Operation {
        AsyncConcurrentOperation(name: event.id.uuidString) { operation in
            Logger.current
                .debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            do {
                try dispatcher.dispatch(event: event) {
                    try await self.persistor.delete(event: event)
                    operation.finish(success: true)
                }
            } catch {
                operation.finish(success: false)
                if operation.currentAttempt <= operation.maximumRetries {
                    operation.manualRetry = true
                    operation.retry()
                }
            }
        }
    }

    private func dispatchPersisted(eventTuple: AsyncQueueEventTuple) async throws {
        guard let dispatcher = dispatchers.first(where: { $0.key == eventTuple.dispatcherId })?.value else {
            try await deletePersistedEvent(filename: eventTuple.filename)
            Logger.current
                .error("Couldn't find dispatcher for persisted event with id: \(eventTuple.dispatcherId)")
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
                Logger.current
                    .debug("Dispatching persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
                try dispatcher.dispatchPersisted(data: event.data) {
                    try await self.deletePersistedEvent(filename: event.filename)
                }
            } catch {
                Logger.current
                    .debug("Failed to dispatch persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            }
        }
    }

    private func loadEvents() async {
        do {
            let events = try await persistor.readAll()
            for event in events {
                try await dispatchPersisted(eventTuple: event)
            }
        } catch {
            Logger.current.debug("Error loading persisted events: \(error)")
        }
    }

    private func deletePersistedEvent(filename: String) async throws {
        try await persistor.delete(filename: filename)
    }
}

#if DEBUG
    public enum MockAsyncQueueDispatcherError: Error {
        case dispatchError
    }

    public class MockAsyncQueueDispatcher: AsyncQueueDispatching {
        public init() {}

        public var invokedIdentifierGetter = false
        public var invokedIdentifierGetterCount = 0
        public var stubbedIdentifier: String! = ""

        public var identifier: String {
            invokedIdentifierGetter = true
            invokedIdentifierGetterCount += 1
            return stubbedIdentifier
        }

        public var invokedDispatch = false
        public var invokedDispatchCallBack: () -> Void = {}
        public var invokedDispatchCount = 0
        public var invokedDispatchParameterEvent: AsyncQueueEvent?
        public var invokedDispatchParametersEventsList = [AsyncQueueEvent]()
        public var stubbedDispatchError: Error?

        public func dispatch(event: AsyncQueueEvent, completion: @escaping () async throws -> Void) throws {
            invokedDispatch = true
            invokedDispatchCount += 1
            invokedDispatchParameterEvent = event
            invokedDispatchParametersEventsList.append(event)
            if let error = stubbedDispatchError {
                invokedDispatchCallBack()
                throw error
            }
            invokedDispatchCallBack()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                try await completion()
                semaphore.signal()
            }
            semaphore.wait()
        }

        public var invokedDispatchPersisted = false
        public var invokedDispatchPersistedCount = 0
        public var invokedDispatchPersistedCallBack: () -> Void = {}
        public var invokedDispatchPersistedDataParameter: Data?
        public var invokedDispatchPersistedParametersDataList = [Data]()
        public var stubbedDispatchPersistedError: Error?

        public func dispatchPersisted(data: Data, completion: @escaping () async throws -> Void) throws {
            invokedDispatchPersisted = true
            invokedDispatchPersistedCount += 1
            invokedDispatchPersistedDataParameter = data
            invokedDispatchPersistedParametersDataList.append(data)
            if let error = stubbedDispatchPersistedError {
                invokedDispatchPersistedCallBack()
                throw error
            }
            invokedDispatchPersistedCallBack()
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                try await completion()
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

#endif
