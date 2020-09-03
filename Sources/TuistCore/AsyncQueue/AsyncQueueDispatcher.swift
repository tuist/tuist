import Foundation
import RxSwift

/// Async queue dispatcher.
public protocol AsyncQueueDispatcher {
    /// Identifier.
    var identifier: String { get }

    /// Dispatches a given event.
    /// - Parameter event: Event to be dispatched.
    func dispatch(event: AsyncQueueEvent) throws

    /// Decodes a given event that has been serialized into disk.
    /// - Parameters:
    ///   - id: Event unique identifier.
    ///   - date: Event date.
    ///   - data: Event content as a data instance.
    func decodeEvent(id: String, date: Date, data: Data) -> AsyncQueueEvent
}
