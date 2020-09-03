import Foundation
import Queuer
import RxSwift
import TuistCore
import TuistSupport

public protocol AsyncQueuing {
    /// It dispatches the given event.
    /// - Parameter event: Event to be dispatched.
    func dispatch(event: AsyncQueueEvent)
}

public class AsyncQueue: AsyncQueuing {
    // MARK: - Attributes

    public static var shared: AsyncQueuing!
    private let queue: Queuer
    private let ciChecker: CIChecking
    private let persistor: AsyncQueuePersisting
    private let dispatchers: [String: AsyncQueueDispatcher]
    private let executionBlock: () throws -> Void

    // MARK: - Init

    public convenience init(dispatchers: [AsyncQueueDispatcher], executionBlock: @escaping () throws -> Void) throws {
        try self.init(queue: Queuer.shared,
                      executionBlock: executionBlock,
                      ciChecker: CIChecker(),
                      persistor: AsyncQueuePersistor(),
                      dispatchers: dispatchers)
    }

    init(queue: Queuer,
         executionBlock: @escaping () throws -> Void,
         ciChecker: CIChecking,
         persistor: AsyncQueuePersisting,
         dispatchers: [AsyncQueueDispatcher]) throws
    {
        self.queue = queue
        self.executionBlock = executionBlock
        self.ciChecker = ciChecker
        self.persistor = persistor
        self.dispatchers = dispatchers.reduce(into: [String: AsyncQueueDispatcher]()) { $0[$1.identifier] = $1 }
        try run()
    }

    // MARK: - AsyncQueuing

    public func dispatch(event: AsyncQueueEvent) {
        dispatch(event: event, persist: true)
    }

    // MARK: - Private

    private func dispatch(event _: AsyncQueueEvent, persist _: Bool = true) {
//        guard let dispatcher = self.dispatchers[event.dispatcherId] else {
//            self.persistor.delete(event: event)
//            logger.debug("Couldn't find dispatcher with id: \(event.dispatcherId)")
//            return
//        }
//
//        // We persist the event in case the dispatching is halted because Tuist's
//        // process exits. In that case we want to retry again the next time there's
//        // opportunity for that.
//        if persist {
//            self.persistor.write(event: event)
//        }
//
//        let operation = ConcurrentOperation(name: event.id.uuidString) { (operation) in
//            logger.debug("Dispatching event with ID '\(event.id.uuidString)' to '\(dispatcher.identifier)'")
//
//            /// The current implementation doesn't support retries but that's something that we can improve in the future.
//            operation.maximumRetries = 1
//
//            /// After the dispatching operation finishes, we delete the event locally.
//            defer { self.persistor.delete(event: event) }
//
//            do {
//                try dispatcher.dispatch(event: event)
//                operation.success = true
//            } catch {
//                operation.success = false
//            }
//        }
//        queue.addOperation(operation)
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
//        persistor.readAll().forEach({ self.dispatch(event: $0, persist: false) })
    }
}
