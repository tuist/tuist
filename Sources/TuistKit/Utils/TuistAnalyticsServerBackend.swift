import FileSystem
import Foundation
import ServiceContextModule
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistServer
import TuistSupport

public class TuistAnalyticsServerBackend: TuistAnalyticsBackend {
    private let fullHandle: String
    private let url: URL
    private let createCommandEventService: CreateCommandEventServicing
    private let fileHandler: FileHandling
    private let ciChecker: CIChecking
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
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
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
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
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing,
        fileSystem: FileSystem
    ) {
        self.fullHandle = fullHandle
        self.url = url
        self.createCommandEventService = createCommandEventService
        self.fileHandler = fileHandler
        self.ciChecker = ciChecker
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.analyticsArtifactUploadService = analyticsArtifactUploadService
        self.fileSystem = fileSystem
    }

    public func send(commandEvent: CommandEvent) async throws {
        let _: ServerCommandEvent = try await send(commandEvent: commandEvent)
    }

    public func send(commandEvent: CommandEvent) async throws -> ServerCommandEvent {
        let serverCommandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: fullHandle,
            serverURL: url
        )
        let runsDirectory = try cacheDirectoriesProvider
            .cacheDirectory(for: .runs)

        let runDirectory = runsDirectory.appending(component: commandEvent.runId)

        let resultBundlePath = commandEvent.resultBundlePath ?? runDirectory
            .appending(component: "\(Constants.resultBundleName).xcresult")

        if try await fileSystem.exists(resultBundlePath) {
            try await analyticsArtifactUploadService.uploadResultBundle(
                resultBundlePath,
                commandEventId: serverCommandEvent.id,
                serverURL: url
            )
        }

        if resultBundlePath.parentDirectory.commonAncestor(with: runsDirectory) == runsDirectory,
           try await fileSystem.exists(resultBundlePath)
        {
            try await fileSystem.remove(resultBundlePath)
        }

        return serverCommandEvent
    }
}
