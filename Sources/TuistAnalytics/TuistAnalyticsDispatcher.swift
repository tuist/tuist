import Foundation
import TuistAsyncQueue
import TuistCore

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported at https://stats.tuist.io/
public struct TuistAnalyticsDispatcher: AsyncQueueDispatching {
    public static let dispatcherId = "TuistAnalytics"

    public init() {}

    // MARK: - AsyncQueueDispatching

    public var identifier = TuistAnalyticsDispatcher.dispatcherId

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () -> Void) throws {
        if let commandEvent = event as? CommandEvent {
            try send(commandEvent: commandEvent) { _, _, _ in
                completion()
            }
        }
    }

    public func dispatchPersisted(data: Data, completion: @escaping () -> Void) throws {
        let decoder = JSONDecoder()
        let commandEvent = try decoder.decode(CommandEvent.self, from: data)
        return try dispatch(event: commandEvent, completion: completion)
    }

    private func send(commandEvent: CommandEvent, completion: @escaping (Data?, URLResponse?, Error?) -> Void) throws {
        var request = URLRequest(url: URL(string: "https://stats.tuist.io/command_events.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let jsonCommandEvent = try encoder.encode(commandEvent)
        request.httpBody = jsonCommandEvent
        let task = URLSession.shared.dataTask(with: request, completionHandler: completion)
        task.resume()
    }
}
