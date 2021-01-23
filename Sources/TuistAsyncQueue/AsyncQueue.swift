import Foundation
import Queuer
import RxSwift
import TuistCore
import TuistSupport

public protocol AsyncQueuing {
    /// It dispatches the given event.
    /// - Parameter event: Event to be dispatched.
    /// - Parameter completion: It's called when the event has been persisted, to make sure it won't get lost
    func dispatch<T: AsyncQueueEvent>(event: T, completion: @escaping () -> ())
}

public class AsyncQueue: AsyncQueuing {
    // MARK: - Attributes
    private let disposeBag: DisposeBag = DisposeBag()
    private let queue: Queuing
    private let ciChecker: CIChecking
    private let persistor: AsyncQueuePersisting
    private var dispatchers: [String: AsyncQueueDispatching] = [:]
    private let persistedEventsSchedulerType: SchedulerType

    public static let sharedInstance: AsyncQueue = AsyncQueue()

    // MARK: - Init

    init(queue: Queuing = Queuer.shared,
         ciChecker: CIChecking = CIChecker(),
         persistor: AsyncQueuePersisting = AsyncQueuePersistor(),
         persistedEventsSchedulerType: SchedulerType = AsyncQueue.schedulerType())
    {
        self.queue = queue
        self.ciChecker = ciChecker
        self.persistor = persistor
        self.persistedEventsSchedulerType = persistedEventsSchedulerType
    }

    public func register(dispatcher: AsyncQueueDispatching) {
        self.dispatchers[dispatcher.identifier] = dispatcher
    }

    // MARK: - AsyncQueuing

    public func start() {
        loadEvents()
        queue.resume()
    }

    public func dispatch<T: AsyncQueueEvent>(event: T, completion: @escaping () -> ()) {
        guard let dispatcher = dispatchers[event.dispatcherId] else {
            logger.error("Couldn't find dispatcher with id: \(event.dispatcherId)")
            return
        }

        // We persist the event in case the dispatching is halted because Tuist's
        // process exits. In that case we want to retry again the next time there's
        // opportunity for that.
        let writeCompletable = persistor.write(event: event)
        _ = writeCompletable.subscribe { _ in
            // Queue event to send
            let operation = self.liveDispatchOperation(event: event, dispatcher: dispatcher)
            self.queue.addOperation(operation)
            completion() // The completion means that the event has been persisted sucessfully, not that it has been sent
        }
    }

    public static func schedulerType() -> SchedulerType {
        SerialDispatchQueueScheduler(queue: dispatchQueue(), internalSerialQueueName: "tuist-async-queue")
    }

    // MARK: - Private

    private func liveDispatchOperation<T: AsyncQueueEvent>(event: T, dispatcher: AsyncQueueDispatching) -> Operation {
        ConcurrentOperation(name: event.id.uuidString) { operation in
            logger.debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
            do {
                try dispatcher.dispatch(event: event) {
                    _ = self.persistor.delete(event: event)
                    operation.success = true
                }
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
                                            dispatcher: AsyncQueueDispatching) -> Operation
    {
        ConcurrentOperation(name: event.id.uuidString) { _ in
            do {
                logger.debug("Dispatching persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
                try dispatcher.dispatchPersisted(data: event.data) {
                    self.deletePersistedEvent(filename: event.filename)
                    print("Deleted persisted \(event.filename)")
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
}
