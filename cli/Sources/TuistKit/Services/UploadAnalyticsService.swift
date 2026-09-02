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
    func upload(
        commandEvent: CommandEvent,
        fullHandle: String,
        serverURL: URL,
        sessionDirectory: AbsolutePath?
    ) async throws -> ServerCommandEvent
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
        serverURL: URL,
        sessionDirectory: AbsolutePath? = nil
    ) async throws -> ServerCommandEvent {
        let runsDirectory = try cacheDirectoriesProvider.cacheDirectory(for: .runs)

        let serverCommandEvent = try await createCommandEventService.createCommandEvent(
            commandEvent: commandEvent,
            projectId: fullHandle,
            serverURL: serverURL
        )

        let (accountHandle, projectHandle) = try fullHandleService.parse(fullHandle)

        if let resultBundlePath = commandEvent.resultBundlePath,
           try await fileSystem.exists(resultBundlePath)
        {
            // The run is over either way, and nothing retries a failed upload, so a bundle kept
            // after one is a bundle kept forever. On a runner's cache volume that leak is what
            // filled the volume; removing the bundle here loses an artifact that was already lost.
            var uploadError: Error?
            do {
                try await analyticsArtifactUploadService.uploadAndAnalyzeResultBundle(
                    resultBundlePath,
                    accountHandle: accountHandle,
                    projectHandle: projectHandle,
                    commandEventId: serverCommandEvent.id,
                    serverURL: serverURL
                )
            } catch {
                uploadError = error
            }
            await removeOwnedRun(at: resultBundlePath, in: runsDirectory)
            if let uploadError { throw uploadError }
        }

        if let sessionDirectory, try await fileSystem.exists(sessionDirectory) {
            try await analyticsArtifactUploadService.uploadSession(
                sessionDirectory,
                accountHandle: accountHandle,
                projectHandle: projectHandle,
                commandEventId: serverCommandEvent.id,
                serverURL: serverURL
            )
        }

        return serverCommandEvent
    }

    /// Removes the run directory a result bundle belongs to, when it is one Tuist created under the
    /// runs cache. A caller-provided `--result-bundle-path` is theirs and is left alone.
    ///
    /// The whole run entry goes, not just the bundle inside it: the run directory is what the
    /// support-cache retention accounts for, and one left behind empty is one it keeps measuring.
    private func removeOwnedRun(at resultBundlePath: AbsolutePath, in runsDirectory: AbsolutePath) async {
        guard resultBundlePath.parentDirectory.commonAncestor(with: runsDirectory) == runsDirectory else { return }
        var run = resultBundlePath
        while run.parentDirectory != runsDirectory {
            run = run.parentDirectory
        }
        try? await fileSystem.remove(run)
    }
}
