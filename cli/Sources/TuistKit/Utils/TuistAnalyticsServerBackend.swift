import FileSystem
import Foundation
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistServer
import TuistSupport

enum TuistAnalyticsServerBackendError: LocalizedError {
    case invalidHandle(String)

    var errorDescription: String? {
        switch self {
        case let .invalidHandle(handle):
            return "The provided handle \(handle) is invalid. It should be in the format 'account/project'."
        }
    }
}

public class TuistAnalyticsServerBackend: TuistAnalyticsBackend {
    private let fullHandle: String
    private let url: URL
    private let createCommandEventService: CreateCommandEventServicing
    private let fileHandler: FileHandling
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
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        analyticsArtifactUploadService: AnalyticsArtifactUploadServicing,
        fileSystem: FileSystem
    ) {
        self.fullHandle = fullHandle
        self.url = url
        self.createCommandEventService = createCommandEventService
        self.fileHandler = fileHandler
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
        let runsDirectory =
            try cacheDirectoriesProvider
                .cacheDirectory(for: .runs)

        let runDirectory = runsDirectory.appending(component: commandEvent.runId)

        let resultBundlePath =
            commandEvent.resultBundlePath
                ?? runDirectory
                .appending(component: "\(Constants.resultBundleName).xcresult")

        let handles = fullHandle.split(separator: "/")
        guard handles.count == 2 else { throw TuistAnalyticsServerBackendError.invalidHandle(fullHandle) }

        if try await fileSystem.exists(resultBundlePath) {
            try await analyticsArtifactUploadService.uploadResultBundle(
                resultBundlePath,
                accountHandle: String(handles[0]),
                projectHandle: String(handles[1]),
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
