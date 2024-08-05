import FileSystem
import Foundation
import Path
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph

public class TuistAnalyticsServerBackend: TuistAnalyticsBackend {
    private let fullHandle: String
    private let url: URL
    private let createCommandEventService: CreateCommandEventServicing
    private let fileHandler: FileHandling
    private let ciChecker: CIChecking
    private let cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring
    private let analyticsArtifactUploadService: AnalyticsArtifactUploadServicing
    private let fileSystem: FileSystem

    public convenience init(
        fullHandle: String,
        url: URL
    ) {
        self.init(
            fullHandle: fullHandle,
            url: url,
            createCommandEventService: CreateCommandEventService(),
            fileHandler: FileHandler.shared,
            ciChecker: CIChecker(),
            cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactory(),
            analyticsArtifactUploadService: AnalyticsArtifactUploadService(),
            fileSystem: FileSystem()
        )
    }

    public init(
        fullHandle: String,
        url: URL,
        createCommandEventService: CreateCommandEventServicing,
        fileHandler: FileHandling,
        ciChecker: CIChecking,
        cacheDirectoriesProviderFactory: CacheDirectoriesProviderFactoring,
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing,
        fileSystem: FileSystem
    ) {
        self.fullHandle = fullHandle
        self.url = url
        self.createCommandEventService = createCommandEventService
        self.fileHandler = fileHandler
        self.ciChecker = ciChecker
        self.cacheDirectoriesProviderFactory = cacheDirectoriesProviderFactory
        self.analyticsArtifactUploadService = analyticsArtifactUploadService
        self.fileSystem = fileSystem
    }

    public func send(commandEvent: CommandEvent) async throws {
        let cloudCommandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: fullHandle,
            serverURL: url
        )

        let runDirectory = try cacheDirectoriesProviderFactory.cacheDirectories()
            .cacheDirectory(for: .runs)
            .appending(component: commandEvent.runId)

        let resultBundle = runDirectory
            .appending(component: "\(Constants.resultBundleName).xcresult")

        if fileHandler.exists(resultBundle),
           let targetHashes = commandEvent.params["target_hashes"]?.value as? [GraphTarget: String],
           let graphPath = commandEvent.params["graph_path"]?.value as? AbsolutePath
        {
            try await analyticsArtifactUploadService.uploadResultBundle(
                resultBundle,
                targetHashes: targetHashes,
                graphPath: graphPath,
                commandEventId: cloudCommandEvent.id,
                serverURL: url
            )
        }

        if fileHandler.exists(runDirectory) {
            try await fileSystem.remove(runDirectory)
        }

        if #available(macOS 13.0, *), ciChecker.isCI() {
            logger
                .info(
                    "You can view a detailed report at: \(cloudCommandEvent.url.absoluteString)"
                )
        }
    }
}
