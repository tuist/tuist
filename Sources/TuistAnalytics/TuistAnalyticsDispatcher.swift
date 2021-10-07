import Foundation
import RxSwift
import TuistAsyncQueue
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

typealias CloudDependencies = (config: Cloud, resourceFactory: CloudAnalyticsResourceFactorying, client: CloudClienting)

/// `TuistAnalyticsTagger` is responsible to send analytics events that gets stored and reported at https://backbone.tuist.io/
public struct TuistAnalyticsDispatcher: AsyncQueueDispatching {
    public static let dispatcherId = "TuistAnalytics"

    private let cloudDependencies: CloudDependencies?
    private let requestDispatcher: HTTPRequestDispatching
    private let disposeBag = DisposeBag()

    public init(cloud: Cloud?) {
        self.init(
            cloudDependencies: cloud.map { (config: $0, resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: $0), client: CloudClient())},
            requestDispatcher: HTTPRequestDispatcher()
        )
    }

    init(
        cloudDependencies: CloudDependencies?,
        requestDispatcher: HTTPRequestDispatching
    ) {
        self.cloudDependencies = cloudDependencies
        self.requestDispatcher = requestDispatcher
    }

    // MARK: - AsyncQueueDispatching

    public var identifier = TuistAnalyticsDispatcher.dispatcherId

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () -> Void) throws {
        guard let commandEvent = event as? CommandEvent else { return }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let encodedCommand = try encoder.encode(commandEvent)
        dispatchPersisted(data: encodedCommand, completion: completion)
    }

    public func dispatchPersisted(data: Data, completion: @escaping () -> Void) {
        Single
            .zip(
                sendToCloud(encodedCommandEvent: data),
                sendToStats(encodedCommandEvent: data)
            )
            .asObservable()
            .subscribe(onNext: { _ in completion() })
            .disposed(by: disposeBag)
    }

    private func sendToStats(encodedCommandEvent: Data) -> Single<Void> {
        var request = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = encodedCommandEvent
        let resource = HTTPResource(
            request: { request },
            parse: { _, _ in Void() },
            parseError: { _, _ in CloudEmptyResponseError() }
        )
        return requestDispatcher.dispatch(resource: resource).flatMap { _, _ in .just(()) }
    }

    private func sendToCloud(encodedCommandEvent: Data) -> Single<Void> {
        guard let cloudDependencies = cloudDependencies,
              cloudDependencies.config.options.contains(.analytics)
        else {
            return .just(())
        }

        let resource = cloudDependencies.resourceFactory.storeResource(encodedCommandEvent: encodedCommandEvent)
        return cloudDependencies.client
            .request(resource)
            .flatMap { _, _ in .just(()) }
    }
}
