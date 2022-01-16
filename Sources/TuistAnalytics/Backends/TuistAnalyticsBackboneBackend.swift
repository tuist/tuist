import Foundation
import TuistAsyncQueue
import TuistCore
import TuistSupport

class TuistAnalyticsBackboneBackend: TuistAnalyticsBackend {
    let requestDispatcher: HTTPRequestDispatching

    init(requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher()) {
        self.requestDispatcher = requestDispatcher
    }

    func send(commandEvent: CommandEvent) async throws {
        _ = try await requestDispatcher.dispatch(resource: resource(commandEvent))
    }

    func resource(_ commandEvent: CommandEvent) throws -> HTTPResource<Void, CloudEmptyResponseError> {
        var request = URLRequest(url: Constants.backboneURL.appendingPathComponent("command_events.json"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedCommandEvent = try encoder.encode(commandEvent)
        request.httpBody = encodedCommandEvent
        return HTTPResource(
            request: { request },
            parse: { _, _ in () },
            parseError: { _, _ in CloudEmptyResponseError() }
        )
    }
}
