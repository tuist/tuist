import Foundation
import TuistAnalytics
import TuistApp
import TuistAsyncQueue
import TuistCore
import TuistGraph
import TuistSupport

public class TuistAnalyticsCloudBackend: TuistAnalyticsBackend {
    private let config: Cloud
    private let createCommandEventService: CreateCommandEventServicing
    private let ciChecker: CIChecking

    public convenience init(config: Cloud) {
        self.init(
            config: config,
            createCommandEventService: CreateCommandEventService()
        )
    }

    public init(
        config: Cloud,
        createCommandEventService: CreateCommandEventServicing,
        ciChecker: CIChecking = CIChecker()
    ) {
        self.config = config
        self.createCommandEventService = createCommandEventService
        self.ciChecker = ciChecker
    }

    public func send(commandEvent: CommandEvent) async throws {
        let commandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: config.projectId,
            serverURL: config.url
        )

        if #available(macOS 13.0, *), ciChecker.isCI() {
            logger
                .info(
                    "You can view a detailed report at: \(commandEvent.url.absoluteString)"
                )
        }
    }
}
