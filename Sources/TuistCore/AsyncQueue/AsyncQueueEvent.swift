import Foundation

public protocol AsyncQueueEvent: Codable {
    /// Unique identifier.
    var id: UUID { get }

    /// The identifier of the dispatcher that should process this event.
    var dispatcherId: String { get }

    /// Event date.
    var date: Date { get }
}

public struct AnyAsyncQueueEvent: AsyncQueueEvent {
    public let id: UUID
    public let dispatcherId: String
    public let date: Date

    public init(id: UUID = UUID(),
                dispatcherId: String,
                date: Date = Date())
    {
        self.id = id
        self.dispatcherId = dispatcherId
        self.date = date
    }
}
