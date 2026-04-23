import ArgumentParser
import FileSystem
import Foundation
import OpenAPIRuntime
import Path
import TuistCache
import TuistCore
import TuistEnvironment
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
    let cacheEndpoint: String
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand {
    private var command: ParsableCommand
    private let clock: Clock
    private let commandArguments: [String]
    private let commandEventFactory: CommandEventFactory
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let uploadAnalyticsService: UploadAnalyticsServicing
    private let fileSystem: FileSysteming
    private let sessionDirectory: AbsolutePath

    public init(
        command: ParsableCommand,
        commandArguments: [String],
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        fileSystem: FileSysteming = FileSystem(),
        sessionDirectory: AbsolutePath
    ) {
        self.command = command
        self.commandArguments = commandArguments
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.backgroundProcessRunner = backgroundProcessRunner
        self.uploadAnalyticsService = uploadAnalyticsService
        self.fileSystem = fileSystem
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
                        try await uploadCommandEvent(
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
                        try await uploadCommandEvent(
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
    ) async throws {
        let durationInSeconds = timer.stop()
        let durationInMs = Int(durationInSeconds * 1000)
        let configuration = type(of: command).configuration
        let (name, subcommand) = extractCommandName(from: configuration)
        let info = await TrackableCommandInfo(
            runId: runId,
            name: name,
            subcommand: subcommand,
            commandArguments: commandArguments,
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
            cacheEndpoint: runMetadataStorage.cacheEndpoint
        )
        let commandEvent = try commandEventFactory.make(
            from: info,
            path: path
        )
        let buildRunURL = await runMetadataStorage.buildRunURL
        if (command as? TrackableParsableCommand)?.analyticsRequired == true || Environment.current.isCI {
            Logger.current.info("Uploading run metadata...")
            do {
                let serverCommandEvent = try await uploadAnalyticsService.upload(
                    commandEvent: commandEvent,
                    fullHandle: fullHandle,
                    serverURL: serverURL,
                    sessionDirectory: sessionDirectory
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
            } catch let error as ClientError {
                Logger.current
                    .warning("Failed to upload run metadata: \(String(describing: error.underlyingError))")
            } catch {
                Logger.current.warning("Failed to upload run metadata: \(String(describing: error))")
            }
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
    }

    private func extractCommandName(from configuration: CommandConfiguration) -> (name: String, subcommand: String?) {
        let name: String
        let subcommand: String?
        if let superCommandName = configuration._superCommandName {
            name = superCommandName
            subcommand = configuration.commandName!
        } else {
            name = configuration.commandName!
            subcommand = nil
        }
        return (name, subcommand)
    }
}
