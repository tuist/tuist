import Foundation
import Queuer
import RxSwift
import TuistCore
import TuistSupport

public protocol AsyncQueuing {
    /// It dispatches the given event.
    /// - Parameter event: Event to be dispatched.
    func dispatch<T: AsyncQueueEvent>(event: T)
}

public class AsyncQueue: AsyncQueuing {
    // MARK: - Attributes

    public static var shared: AsyncQueuing!
    private let disposeBag: DisposeBag = DisposeBag()
    private let queue: Queuing
    private let ciChecker: CIChecking
    private let persistor: AsyncQueuePersisting
    private let dispatchers: [String: AsyncQueueDispatching]
    private let executionBlock: () throws -> Void
    private let persistedEventsSchedulerType: SchedulerType

    // MARK: - Init

    public convenience init(dispatchers: [AsyncQueueDispatching],
                            executionBlock: @escaping () throws -> Void) throws {
        try self.init(queue: Queuer.shared,
                      executionBlock: executionBlock,
                      ciChecker: CIChecker(),
                      persistor: AsyncQueuePersistor(),
                      dispatchers: dispatchers)
    }

    init(queue: Queuing,
         executionBlock: @escaping () throws -> Void,
         ciChecker: CIChecking,
         persistor: AsyncQueuePersisting,
         dispatchers: [AsyncQueueDispatching],
         persistedEventsSchedulerType: SchedulerType = AsyncQueue.schedulerType()) throws {
        self.queue = queue
        self.executionBlock = executionBlock
        self.ciChecker = ciChecker
        self.persistor = persistor
        self.dispatchers = dispatchers.reduce(into: [String: AsyncQueueDispatching]()) { $0[$1.identifier] = $1 }
        self.persistedEventsSchedulerType = persistedEventsSchedulerType
        try run()
    }

    // MARK: - AsyncQueuing

    public func dispatch<T: AsyncQueueEvent>(event: T) {
        guard let dispatcher = dispatchers[event.dispatcherId] else {
            logger.error("Couldn't find dispatcher with id: \(event.dispatcherId)")
            return
        }

        // We persist the event in case the dispatching is halted because Tuist's
        // process exits. In that case we want to retry again the next time there's
        // opportunity for that.
        _ = persistor.write(event: event)

        // Queue event to send
        let operation = liveDispatchOperation(event: event, dispatcher: dispatcher)
        queue.addOperation(operation)
    }

    // MARK: - Private

    private func liveDispatchOperation<T: AsyncQueueEvent>(event: T, dispatcher: AsyncQueueDispatching) -> Operation {
        ConcurrentOperation(name: event.id.uuidString) { operation in
            logger.debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")

            do {
                try dispatcher.dispatch(event: event)
                operation.success = true

                /// After the dispatching operation finishes, we delete the event locally.
                _ = self.persistor.delete(event: event)
            } catch {
                operation.success = false
            }
        }
    }

    private func dispatchPersisted(eventTuple: AsyncQueueEventTuple) {
        guard let dispatcher = dispatchers.first(where: { $0.key == eventTuple.dispatcherId })?.value else {
            deletePersistedEvent(filename: eventTuple.filename)
            logger.error("Couldn't find dispatcher for persisted event with id: \(eventTuple.dispatcherId)")
            return
        }

        let operation = persistedDispatchOperation(event: eventTuple, dispatcher: dispatcher)
        queue.addOperation(operation)
    }

    private func persistedDispatchOperation(event: AsyncQueueEventTuple,
                                            dispatcher: AsyncQueueDispatching) -> Operation {
        ConcurrentOperation(name: event.id.uuidString) { _ in
            /// After the dispatching operation finishes, we delete the event locally.
            defer { self.deletePersistedEvent(filename: event.filename) }

            do {
                logger.debug("Dispatching persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
                try dispatcher.dispatchPersisted(data: event.data)
            } catch {
                logger.debug("Failed to dispatch persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            }
        }
    }

    private func run() throws {
        start()
        do {
            try executionBlock()
            waitIfCI()
        } catch {
            waitIfCI()
            throw error
        }
    }

    private func start() {
        loadEvents()
        queue.resume()
    }

    private func waitIfCI() {
        if !ciChecker.isCI() { return }
        queue.waitUntilAllOperationsAreFinished()
    }

    private func loadEvents() {
        persistor
            .readAll()
            .subscribeOn(persistedEventsSchedulerType)
            .subscribe(onSuccess: { events in
                events.forEach(self.dispatchPersisted)
            }, onError: { error in
                logger.debug("Error loading persisted events: \(error)")
            })
            .disposed(by: disposeBag)
    }

    private func deletePersistedEvent(filename: String) {
        persistor.delete(filename: filename).subscribe().disposed(by: disposeBag)
    }

    // MARK: Private & Static

    private static func dispatchQueue() -> DispatchQueue {
        DispatchQueue(label: "io.tuist.async-queue", qos: .background)
    }

    private static func schedulerType() -> SchedulerType {
        ConcurrentDispatchQueueScheduler(queue: dispatchQueue())
    }
}
