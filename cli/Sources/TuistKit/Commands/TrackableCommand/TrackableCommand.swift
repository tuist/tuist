import ArgumentParser
import FileSystem
import Foundation
import OpenAPIRuntime
import Path
import TuistAlert
import TuistCache
import TuistCore
import TuistEnvironment
import TuistJobSummary
import TuistLogging
import TuistProcess
import TuistServer
import TuistSupport
import XcodeGraph

/// `TrackableCommandInfo` contains the information to report the execution of a command
public struct TrackableCommandInfo {
    let runId: String
    let name: String
    let subcommand: String?
    let commandArguments: [String]
    let durationInMs: Int
    let status: CommandEvent.Status
    let graph: Graph?
    let graphBinaryBuildDuration: TimeInterval?
    let binaryCacheItems: [AbsolutePath: [String: CacheItem]]
    let selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]
    let targetContentHashSubhashes: [String: TargetContentHashSubhashes]
    let previewId: String?
    let resultBundlePath: AbsolutePath?
    let ranAt: Date
    let buildRunId: String?
    let testRunId: String?
    let generationId: String?
    let cacheEndpoint: String
    let moduleCacheTransfers: [ModuleCacheTransfer]
    let moduleCacheTransferDuration: TimeInterval?
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand {
    private var command: ParsableCommand
    private let clock: Clock
    private let commandArguments: [String]
    private let commandEventFactory: CommandEventFactory
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let uploadAnalyticsService: UploadAnalyticsServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let fileSystem: FileSysteming
    private let gitHubActionsJobSummaryService: GitHubActionsJobSummaryServicing
    private let bestEffortForegroundUploadTimeout: Duration
    private let sessionDirectory: AbsolutePath

    public init(
        command: ParsableCommand,
        commandArguments: [String],
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        fileSystem: FileSysteming = FileSystem(),
        gitHubActionsJobSummaryService: GitHubActionsJobSummaryServicing = GitHubActionsJobSummaryService(),
        bestEffortForegroundUploadTimeout: Duration = .seconds(15),
        sessionDirectory: AbsolutePath
    ) {
        self.command = command
        self.commandArguments = commandArguments
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.backgroundProcessRunner = backgroundProcessRunner
        self.uploadAnalyticsService = uploadAnalyticsService
        self.serverAuthenticationController = serverAuthenticationController
        self.fileSystem = fileSystem
        self.gitHubActionsJobSummaryService = gitHubActionsJobSummaryService
        self.bestEffortForegroundUploadTimeout = bestEffortForegroundUploadTimeout
        self.sessionDirectory = sessionDirectory
    }

    public func run(
        fullHandle: String?,
        serverURL: URL?,
        shouldTrackAnalytics: Bool,
        optionalAuthentication: Bool = false
    ) async throws {
        let timer = clock.startTimer()
        let ranAt = clock.now
        let path = try await CommandArguments.path(in: commandArguments)
        let runMetadataStorage = RunMetadataStorage()
        let usesOptionalAuthentication =
            optionalAuthentication
                && (((command as? TrackableParsableCommand)?.analyticsRequired == true) || Environment.current.isCI)
        try await ServerAuthenticationConfig.withOptionalAuthentication(usesOptionalAuthentication) {
            try await RunMetadataStorage.$current.withValue(runMetadataStorage) {
                do {
                    if var asyncCommand = command as? AsyncParsableCommand {
                        try await asyncCommand.run()
                    } else {
                        try command.run()
                    }
                    if let fullHandle, let serverURL, shouldTrackAnalytics {
                        await uploadCommandEvent(
                            timer: timer,
                            status: .success,
                            runId: runMetadataStorage.runId,
                            path: path,
                            runMetadataStorage: runMetadataStorage,
                            fullHandle: fullHandle,
                            serverURL: serverURL,
                            ranAt: ranAt
                        )
                    }
                } catch {
                    if let fullHandle, let serverURL, shouldTrackAnalytics {
                        await uploadCommandEvent(
                            timer: timer,
                            status: .failure("\(error)"),
                            runId: await runMetadataStorage.runId,
                            path: path,
                            runMetadataStorage: runMetadataStorage,
                            fullHandle: fullHandle,
                            serverURL: serverURL,
                            ranAt: ranAt
                        )
                    }
                    throw error
                }
            }
        }
    }

    private func uploadCommandEvent(
        timer: any ClockTimer,
        status: CommandEvent.Status,
        runId: String,
        path: AbsolutePath,
        runMetadataStorage: RunMetadataStorage,
        fullHandle: String,
        serverURL: URL,
        ranAt: Date
    ) async {
        do {
            if ServerAuthenticationConfig.current.optionalAuthentication {
                let token = try? await serverAuthenticationController.authenticationToken(
                    serverURL: serverURL,
                    refreshIfNeeded: false
                )
                if token == nil {
                    Logger.current.debug("Skipping run metadata upload: no authentication credentials available.")
                    return
                }
            }

            let durationInSeconds = timer.stop()
            let durationInMs = Int(durationInSeconds * 1000)
            let configuration = type(of: command).configuration
            let commandMetadata = await analyticsCommandMetadata(
                from: configuration,
                runMetadataStorage: runMetadataStorage
            )
            let info = await TrackableCommandInfo(
                runId: runId,
                name: commandMetadata.name,
                subcommand: commandMetadata.subcommand,
                commandArguments: commandMetadata.commandArguments,
                durationInMs: durationInMs,
                status: status,
                graph: runMetadataStorage.graph,
                graphBinaryBuildDuration: runMetadataStorage.graphBinaryBuildDuration,
                binaryCacheItems: runMetadataStorage.binaryCacheItems,
                selectiveTestingCacheItems: runMetadataStorage.selectiveTestingCacheItems,
                targetContentHashSubhashes: runMetadataStorage.targetContentHashSubhashes,
                previewId: runMetadataStorage.previewId,
                resultBundlePath: runMetadataStorage.resultBundlePath,
                ranAt: ranAt,
                buildRunId: runMetadataStorage.buildRunId,
                testRunId: runMetadataStorage.testRunId,
                generationId: runMetadataStorage.generationId,
                cacheEndpoint: runMetadataStorage.cacheEndpoint,
                moduleCacheTransfers: runMetadataStorage.moduleCacheTransfers,
                moduleCacheTransferDuration: runMetadataStorage.moduleCacheTransferDuration
            )
            let commandEvent = try await commandEventFactory.make(
                from: info,
                path: path
            )
            let buildRunURL = await runMetadataStorage.buildRunURL
            let isAnalyticsRequired = (command as? TrackableParsableCommand)?.analyticsRequired == true
            if isAnalyticsRequired || Environment.current.isCI {
                Logger.current.info("Uploading run metadata...")
                let serverCommandEvent = try await uploadCommandEvent(
                    commandEvent,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    isAnalyticsRequired: isAnalyticsRequired
                )
                if let testRunURL = serverCommandEvent.testRunURL {
                    Logger.current
                        .info(
                            "You can view a detailed test report at: \(testRunURL.absoluteString)"
                        )
                } else if let buildRunURL {
                    Logger.current
                        .info(
                            "Build uploaded for processing. You can view the build report at: \(buildRunURL.absoluteString)"
                        )
                } else {
                    Logger.current
                        .info(
                            "You can view a detailed run report at: \(serverCommandEvent.url.absoluteString)"
                        )
                }

                let testRunReports = await runMetadataStorage.testRunReports
                let buildRunReports = await runMetadataStorage.buildRunReports
                await gitHubActionsJobSummaryService.writeJobSummary(
                    testRunReports: testRunReports,
                    buildRunReports: buildRunReports,
                    runURL: serverCommandEvent.url
                )
            } else {
                let tempDirectory = try await fileSystem.makeTemporaryDirectory(prefix: "analytics")
                let commandEventPath = tempDirectory.appending(component: "command-event.json")
                try await fileSystem.writeAsJSON(commandEvent, at: commandEventPath)
                try backgroundProcessRunner.runInBackground(
                    [Environment.current.currentExecutablePath()?.pathString ?? "tuist"] + [
                        "analytics-upload",
                        commandEventPath.pathString,
                        fullHandle,
                        serverURL.absoluteString,
                        sessionDirectory.pathString,
                    ],
                    environment: ProcessInfo.processInfo.environment
                )
            }
        } catch let error as ClientError {
            Logger.current.warning("Failed to upload run metadata: \(String(describing: error.underlyingError))")
        } catch let error as TrackableCommandUploadError {
            Logger.current.warning("Failed to upload run metadata: \(error.localizedDescription)")
        } catch {
            Logger.current.warning("Failed to upload run metadata: \(String(describing: error))")
        }
    }

    private func uploadCommandEvent(
        _ commandEvent: CommandEvent,
        fullHandle: String,
        serverURL: URL,
        isAnalyticsRequired: Bool
    ) async throws -> ServerCommandEvent {
        if isAnalyticsRequired {
            return try await uploadAnalyticsService.upload(
                commandEvent: commandEvent,
                fullHandle: fullHandle,
                serverURL: serverURL,
                sessionDirectory: sessionDirectory
            )
        }

        var serverCommandEvent: ServerCommandEvent?
        try await withTimeout(
            bestEffortForegroundUploadTimeout,
            onTimeout: {
                throw TrackableCommandUploadError.bestEffortUploadTimedOut
            }
        ) {
            serverCommandEvent = try await self.uploadAnalyticsService.upload(
                commandEvent: commandEvent,
                fullHandle: fullHandle,
                serverURL: serverURL,
                sessionDirectory: self.sessionDirectory
            )
        }
        guard let serverCommandEvent else {
            throw TrackableCommandUploadError.bestEffortUploadTimedOut
        }
        return serverCommandEvent
    }

    private func analyticsCommandMetadata(
        from configuration: CommandConfiguration,
        runMetadataStorage: RunMetadataStorage
    ) async -> AnalyticsCommandMetadata {
        if let resolvedCommandMetadata = await runMetadataStorage.resolvedCommandMetadata {
            return resolvedCommandMetadata
        }

        let fallbackName = commandArguments.first ?? String(describing: type(of: command))
        let fallbackSubcommand = commandArguments.dropFirst().first.flatMap { argument in
            argument.hasPrefix("-") ? nil : argument
        }

        if let superCommandName = configuration._superCommandName {
            return AnalyticsCommandMetadata(
                name: superCommandName,
                subcommand: configuration.commandName ?? fallbackSubcommand,
                commandArguments: commandArguments
            )
        }

        if let commandName = configuration.commandName {
            return AnalyticsCommandMetadata(
                name: commandName,
                subcommand: nil,
                commandArguments: commandArguments
            )
        }

        AlertController.current.warning(
            .alert("Failed to resolve canonical command metadata for analytics. Falling back to command arguments.")
        )
        return AnalyticsCommandMetadata(
            name: fallbackName,
            subcommand: fallbackSubcommand,
            commandArguments: commandArguments
        )
    }
}

private enum TrackableCommandUploadError: LocalizedError {
    case bestEffortUploadTimedOut

    var errorDescription: String? {
        switch self {
        case .bestEffortUploadTimedOut:
            return "Run metadata upload timed out."
        }
    }
}
