import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistHTTP
import TuistServer
import TuistSupport

@Mockable
public protocol UploadAnalyticsServicing {
    @discardableResult
    func upload(commandEvent: CommandEvent, fullHandle: String, serverURL: URL) async throws -> ServerCommandEvent
}

public struct UploadAnalyticsService: UploadAnalyticsServicing {
    private let createCommandEventService: CreateCommandEventServicing
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let analyticsArtifactUploadService: AnalyticsArtifactUploadServicing
    private let fullHandleService: FullHandleServicing
    private let fileSystem: FileSysteming

    public init(
        createCommandEventService: CreateCommandEventServicing = CreateCommandEventService(),
        cacheDirectoriesProvider: CacheDirectoriesProviding = CacheDirectoriesProvider(),
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing = AnalyticsArtifactUploadService(),
        fullHandleService: FullHandleServicing = FullHandleService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.createCommandEventService = createCommandEventService
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.analyticsArtifactUploadService = analyticsArtifactUploadService
        self.fullHandleService = fullHandleService
        self.fileSystem = fileSystem
    }

    @discardableResult
    public func upload(
        commandEvent: CommandEvent,
        fullHandle: String,
        serverURL: URL
    ) async throws -> ServerCommandEvent {
        let runsDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .runs)
        let runDirectory = runsDirectory.appending(component: commandEvent.runId)
        let resultBundlePath = commandEvent.resultBundlePath
            ?? runDirectory.appending(component: "\(Constants.resultBundleName).xcresult")

        let serverCommandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: fullHandle,
            serverURL: serverURL
        )

        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)

        if try await fileSystem.exists(resultBundlePath) {
            try await analyticsArtifactUploadService.uploadResultBundle(
                resultBundlePath,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                commandEventId: serverCommandEvent.id,
                serverURL: serverURL
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
