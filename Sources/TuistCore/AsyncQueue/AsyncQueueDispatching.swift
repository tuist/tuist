import Foundation
import RxSwift

/// Async queue dispatcher.
public protocol AsyncQueueDispatching {
    /// Identifier.
    var identifier: String { get }

    /// Dispatches a given event.
    /// - Parameter event: Event to be dispatched.
    func dispatch(event: AsyncQueueEvent, completion: @escaping () -> Void) throws

    /// Dispatch a persisted event.
    /// - Parameter data: Serialized data of the event.
    func dispatchPersisted(data: Data, completion: @escaping () -> Void) throws
}
