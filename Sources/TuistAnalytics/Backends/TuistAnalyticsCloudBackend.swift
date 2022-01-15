import Foundation
import RxSwift
import TuistAsyncQueue
import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

class TuistAnalyticsCloudBackend: TuistAnalyticsBackend {
    let config: Cloud
    let resourceFactory: CloudAnalyticsResourceFactorying
    let client: CloudClienting

    public convenience init(config: Cloud) {
        self.init(
            config: config,
            resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: config),
            client: CloudClient()
        )
    }

    public init(config: Cloud,
                resourceFactory: CloudAnalyticsResourceFactorying,
                client: CloudClienting)
    {
        self.config = config
        self.resourceFactory = resourceFactory
        self.client = client
    }

    func send(commandEvent: CommandEvent) throws -> Single<Void> {
        guard config.options.contains(.analytics) else { return .just(()) }

        let resource = try resourceFactory.create(commandEvent: commandEvent)
        return AsyncThrowingStream<Void, Error> { continuation in
            Task.detached {
                do {
                    _ = try await self.client.request(resource)
                    continuation.yield(())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }.asObservable().asSingle()
    }
}
