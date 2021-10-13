import Foundation
import RxSwift
import TuistAsyncQueue
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

protocol TuistAnalyticsBackend {
    func send(commandEvent: CommandEvent) throws -> Single<Void>
}

struct TuistAnalyticsBackboneBackend: TuistAnalyticsBackend {
    let requestDispatcher: HTTPRequestDispatching

    func send(commandEvent: CommandEvent) throws -> Single<Void> {
        var request = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedCommandEvent = try encoder.encode(commandEvent)
        request.httpBody = encodedCommandEvent
        let resource = HTTPResource(
            request: { request },
            parse: { _, _ in Void() },
            parseError: { _, _ in CloudEmptyResponseError() }
        )
        return requestDispatcher.dispatch(resource: resource).flatMap { _, _ in .just(()) }
    }
}

struct TuistAnalyticsCloudBackend: TuistAnalyticsBackend {
    let config: Cloud
    let resourceFactory: CloudAnalyticsResourceFactorying
    let client: CloudClienting

    func send(commandEvent: CommandEvent) throws -> Single<Void> {
        guard config.options.contains(.analytics) else { return .just(()) }

        let resource = try resourceFactory.storeResource(commandEvent: commandEvent)
        return client
            .request(resource)
            .flatMap { _, _ in .just(()) }
    }
}
