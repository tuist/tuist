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
    private let dispatchQueue: DispatchQueue!
    private let queue: Queuer
    private let ciChecker: CIChecking
    private let persistor: AsyncQueuePersisting
    private let dispatchers: [String: AsyncQueueDispatcher]
    private let executionBlock: () throws -> Void

    // MARK: - Init

    public static func dispatchQueue() -> DispatchQueue {
        .init(label: "io.tuist.async-queue", qos: .background)
    }

    public convenience init(dispatchers: [AsyncQueueDispatcher],
                            dispatchQueue: DispatchQueue = AsyncQueue.dispatchQueue(),
                            executionBlock: @escaping () throws -> Void) throws
    {
        try self.init(queue: Queuer.shared,
                      dispatchQueue: dispatchQueue,
                      executionBlock: executionBlock,
                      ciChecker: CIChecker(),
                      persistor: AsyncQueuePersistor(),
                      dispatchers: dispatchers)
    }

    init(queue: Queuer,
         dispatchQueue: DispatchQueue,
         executionBlock: @escaping () throws -> Void,
         ciChecker: CIChecking,
         persistor: AsyncQueuePersisting,
         dispatchers: [AsyncQueueDispatcher]) throws
    {
        self.queue = queue
        self.dispatchQueue = dispatchQueue
        self.executionBlock = executionBlock
        self.ciChecker = ciChecker
        self.persistor = persistor
        self.dispatchers = dispatchers.reduce(into: [String: AsyncQueueDispatcher]()) { $0[$1.identifier] = $1 }
        try run()
    }

    // MARK: - AsyncQueuing

    public func dispatch<T: AsyncQueueEvent>(event: T) {
        dispatch(event: event, persist: true)
    }

    // MARK: - Private

    private func dispatchPersisted(event: AsyncQueueEventTuple) {
        let delete = {
            self.persistor.delete(filename: event.filename).subscribe().disposed(by: self.disposeBag)
        }

        dispatchQueue.async {
            guard let dispatcher = self.dispatchers.first(where: { $0.key == event.dispatcherId })?.value else {
                delete()
                logger.error("Couldn't find dispatcher with id: \(event.dispatcherId)")
                return
            }
            do {
                logger.debug("Dispatching persisted event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
                try dispatcher.dispatchPersisted(data: event.data)
            } catch {
                delete()
            }
        }
    }

    private func dispatch<T: AsyncQueueEvent>(event: T, persist: Bool = true) {
        let delete = {
            self.persistor.delete(event: event).subscribe().disposed(by: self.disposeBag)
        }

        guard let dispatcher = dispatchers[event.dispatcherId] else {
            delete()
            logger.error("Couldn't find dispatcher with id: \(event.dispatcherId)")
            return
        }

        // We persist the event in case the dispatching is halted because Tuist's
        // process exits. In that case we want to retry again the next time there's
        // opportunity for that.
        if persist {
            _ = persistor.write(event: event)
        }

        let operation = ConcurrentOperation(name: event.id.uuidString) { operation in
            logger.debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")

            /// The current implementation doesn't support retries but that's something that we can improve in the future.
            operation.maximumRetries = 1

            /// After the dispatching operation finishes, we delete the event locally.
            defer { _ = self.persistor.delete(event: event) }

            do {
                try dispatcher.dispatch(event: event)
                operation.success = true
            } catch {
                operation.success = false
            }
        }
        queue.addOperation(operation)
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
            .subscribeOn(scheduler())
            .subscribe(onSuccess: { events in
                events.forEach(self.dispatchPersisted)
            }, onError: { error in
                logger.debug("Error loading persisted events: \(error)")
            })
            .disposed(by: disposeBag)
    }

    private func scheduler() -> ConcurrentDispatchQueueScheduler {
        ConcurrentDispatchQueueScheduler(queue: dispatchQueue)
    }
}
