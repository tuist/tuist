import Foundation
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

public class TuistAnalyticsCloudBackend: TuistAnalyticsBackend {
    private let config: Cloud
    private let createCommandEventService: CreateCommandEventServicing
    private let fileHandler: FileHandling
    private let ciChecker: CIChecking
    private let cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring
    private let analyticsArtifactUploadService: AnalyticsArtifactUploadServicing

    public convenience init(config: Cloud) {
        self.init(
            config: config,
            createCommandEventService: CreateCommandEventService(),
            fileHandler: FileHandler.shared,
            ciChecker: CIChecker(),
            cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactory(),
            analyticsArtifactUploadService: AnalyticsArtifactUploadService()
        )
    }

    public init(
        config: Cloud,
        createCommandEventService: CreateCommandEventServicing,
        fileHandler: FileHandling,
        ciChecker: CIChecking,
        cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring,
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing
    ) {
        self.config = config
        self.createCommandEventService = createCommandEventService
        self.fileHandler = fileHandler
        self.ciChecker = ciChecker
        self.cacheDirectoriesProviderFactory = cacheDirectoriesProviderFactory
        self.analyticsArtifactUploadService = analyticsArtifactUploadService
    }

    public func send(commandEvent: CommandEvent) async throws {
        let cloudCommandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: config.projectId,
            serverURL: config.url
        )

        let runDirectory = try cacheDirectoriesProviderFactory.cacheDirectories()
            .tuistCacheDirectory(for: .runs)
            .appending(component: commandEvent.runId)

        let resultBundle = runDirectory
            .appending(component: "\(Constants.resultBundleName).xcresult")

        if fileHandler.exists(resultBundle) {
            try await analyticsArtifactUploadService.uploadAnalyticsArtifact(
                artifactPath: resultBundle,
                commandEventId: cloudCommandEvent.id,
                serverURL: config.url
            )
        }

        if fileHandler.exists(runDirectory) {
            try fileHandler.delete(runDirectory)
        }

        if #available(macOS 13.0, *), ciChecker.isCI() {
            logger
                .info(
                    "You can view a detailed report at: \(cloudCommandEvent.url.absoluteString)"
                )
        }
    }
}
