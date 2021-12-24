import Foundation
import RxSwift
import TuistAsyncQueue
import TuistCore
import TuistSupport

class TuistAnalyticsBackboneBackend: TuistAnalyticsBackend {
    let requestDispatcher: HTTPRequestDispatching

    init(requestDispatcher: HTTPRequestDispatching = HTTPRequestDispatcher()) {
        self.requestDispatcher = requestDispatcher
    }

    func send(commandEvent: CommandEvent) throws -> Single<Void> {
        requestDispatcher
            .dispatch(resource: try resource(commandEvent))
            .flatMap { _, _ in .just(()) }
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
