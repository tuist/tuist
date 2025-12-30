import ArgumentParser
import FileSystem
import Foundation
import OpenAPIRuntime
import Path
import TuistCache
import TuistCore
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
    private let fileHandler: FileHandling
    private let backgroundProcessRunner: BackgroundProcessRunning
    private let uploadAnalyticsService: UploadAnalyticsServicing
    private let fileSystem: FileSysteming

    public init(
        command: ParsableCommand,
        commandArguments: [String],
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        fileHandler: FileHandling = FileHandler.shared,
        backgroundProcessRunner: BackgroundProcessRunning = BackgroundProcessRunner(),
        uploadAnalyticsService: UploadAnalyticsServicing = UploadAnalyticsService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.command = command
        self.commandArguments = commandArguments
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.fileHandler = fileHandler
        self.backgroundProcessRunner = backgroundProcessRunner
        self.uploadAnalyticsService = uploadAnalyticsService
        self.fileSystem = fileSystem
    }

    public func run(
        fullHandle: String?,
        serverURL: URL?,
        shouldTrackAnalytics: Bool
    ) async throws {
        let timer = clock.startTimer()
        let ranAt = clock.now
        let pathIndex = commandArguments.firstIndex(of: "--path")
        let path: AbsolutePath
        if let pathIndex, commandArguments.endIndex > pathIndex + 1 {
            path = try AbsolutePath(validating: commandArguments[pathIndex + 1], relativeTo: fileHandler.currentPath)
        } else {
            path = fileHandler.currentPath
        }
        let runMetadataStorage = RunMetadataStorage()
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
                        serverURL: serverURL
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
                        serverURL: serverURL
                    )
                }
                throw error
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
        serverURL: URL
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
            ranAt: Date(),
            buildRunId: runMetadataStorage.buildRunId,
            testRunId: runMetadataStorage.testRunId,
            cacheEndpoint: runMetadataStorage.cacheEndpoint
        )
        let commandEvent = try commandEventFactory.make(
            from: info,
            path: path
        )
        if (command as? TrackableParsableCommand)?.analyticsRequired == true || Environment.current.isCI {
            Logger.current.info("Uploading run metadata...")
            do {
                let serverCommandEvent = try await uploadAnalyticsService.upload(
                    commandEvent: commandEvent,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
                if let testRunURL = serverCommandEvent.testRunURL {
                    Logger.current
                        .info(
                            "You can view a detailed test report at: \(testRunURL.absoluteString)"
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
