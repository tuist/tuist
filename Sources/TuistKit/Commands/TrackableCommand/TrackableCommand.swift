import ArgumentParser
import Foundation
import Path
import ServiceContextModule
import TuistAnalytics
import TuistAsyncQueue
import TuistCache
import TuistCore
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
    let binaryCacheItems: [AbsolutePath: [String: CacheItem]]
    let selectiveTestingCacheItems: [AbsolutePath: [String: CacheItem]]
    let previewId: String?
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand {
    private var command: ParsableCommand
    private let clock: Clock
    private let commandArguments: [String]
    private let commandEventFactory: CommandEventFactory
    private let asyncQueue: AsyncQueuing
    private let fileHandler: FileHandling

    public init(
        command: ParsableCommand,
        commandArguments: [String],
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        asyncQueue: AsyncQueuing = AsyncQueue.sharedInstance,
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.command = command
        self.commandArguments = commandArguments
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.asyncQueue = asyncQueue
        self.fileHandler = fileHandler
    }

    public func run(
        analyticsEnabled: Bool
    ) async throws {
        let timer = clock.startTimer()
        let pathIndex = commandArguments.firstIndex(of: "--path")
        let path: AbsolutePath
        if let pathIndex, commandArguments.endIndex > pathIndex + 1 {
            path = try AbsolutePath(validating: commandArguments[pathIndex + 1], relativeTo: fileHandler.currentPath)
        } else {
            path = fileHandler.currentPath
        }
        let runMetadataStorage = RunMetadataStorage()
        var context = ServiceContext.current ?? ServiceContext.topLevel
        context.runMetadataStorage = runMetadataStorage
        try await ServiceContext.withValue(context) {
            do {
                if var asyncCommand = command as? AsyncParsableCommand {
                    try await asyncCommand.run()
                } else {
                    try command.run()
                }
                if analyticsEnabled {
                    try await dispatchCommandEvent(
                        timer: timer,
                        status: .success,
                        runId: runMetadataStorage.runId,
                        path: path,
                        runMetadataStorage: runMetadataStorage
                    )
                }
            } catch {
                if analyticsEnabled {
                    try await dispatchCommandEvent(
                        timer: timer,
                        status: .failure("\(error)"),
                        runId: await runMetadataStorage.runId,
                        path: path,
                        runMetadataStorage: runMetadataStorage
                    )
                }
                throw error
            }
        }
    }

    private func dispatchCommandEvent(
        timer: any ClockTimer,
        status: CommandEvent.Status,
        runId: String,
        path: AbsolutePath,
        runMetadataStorage: RunMetadataStorage
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
            binaryCacheItems: runMetadataStorage.binaryCacheItems,
            selectiveTestingCacheItems: runMetadataStorage.selectiveTestingCacheItems,
            previewId: runMetadataStorage.previewId
        )
        let commandEvent = try commandEventFactory.make(
            from: info,
            path: path
        )
        try asyncQueue.dispatch(event: commandEvent)
        if let command = command as? TrackableParsableCommand, command.analyticsRequired {
            asyncQueue.wait()
        } else {
            asyncQueue.waitIfCI()
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
