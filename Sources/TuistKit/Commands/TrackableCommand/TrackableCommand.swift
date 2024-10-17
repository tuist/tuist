import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistSupport

/// `TrackableCommandInfo` contains the information to report the execution of a command
public struct TrackableCommandInfo {
    let runId: String
    let name: String
    let subcommand: String?
    let parameters: [String: AnyCodable]
    let commandArguments: [String]
    let durationInMs: Int
    let status: CommandEvent.Status
    let targetHashes: [CommandEventGraphTarget: String]?
    let graphPath: AbsolutePath?
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand: TrackableParametersDelegate {
    public var targetHashes: [CommandEventGraphTarget: String]?
    public var graphPath: AbsolutePath?

    private var command: ParsableCommand
    private let clock: Clock
    private var trackedParameters: [String: AnyCodable] = [:]
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
        let runId: String
        let timer = clock.startTimer()
        if let command = command as? HasTrackableParameters & ParsableCommand {
            type(of: command).analyticsDelegate = self
            runId = command.runId
            self.command = command
        } else {
            runId = UUID().uuidString
        }
        let pathIndex = commandArguments.firstIndex(of: "--path")
        let path: AbsolutePath
        if let pathIndex, commandArguments.endIndex > pathIndex + 1 {
            path = try AbsolutePath(validating: commandArguments[pathIndex + 1], relativeTo: fileHandler.currentPath)
        } else {
            path = fileHandler.currentPath
        }
        do {
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            if analyticsEnabled {
                try dispatchCommandEvent(
                    timer: timer,
                    status: .success,
                    runId: runId,
                    path: path
                )
            }
        } catch {
            if analyticsEnabled {
                try dispatchCommandEvent(
                    timer: timer,
                    status: .failure("\(error)"),
                    runId: runId,
                    path: path
                )
            }
            throw error
        }
    }

    private func dispatchCommandEvent(
        timer: any ClockTimer,
        status: CommandEvent.Status,
        runId: String,
        path: AbsolutePath
    ) throws {
        let durationInSeconds = timer.stop()
        let durationInMs = Int(durationInSeconds * 1000)
        let configuration = type(of: command).configuration
        let (name, subcommand) = extractCommandName(from: configuration)
        let info = TrackableCommandInfo(
            runId: runId,
            name: name,
            subcommand: subcommand,
            parameters: trackedParameters,
            commandArguments: commandArguments,
            durationInMs: durationInMs,
            status: status,
            targetHashes: targetHashes,
            graphPath: graphPath
        )
        let commandEvent = try commandEventFactory.make(
            from: info,
            path: path
        )
        try asyncQueue.dispatch(event: commandEvent)
        asyncQueue.waitIfCI()
    }

    public func addParameters(_ parameters: [String: AnyCodable]) {
        trackedParameters.merge(
            parameters,
            uniquingKeysWith: { _, newKey in newKey }
        )
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
