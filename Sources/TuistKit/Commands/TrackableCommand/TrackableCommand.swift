import AnyCodable
import ArgumentParser
import Foundation
import TuistAsyncQueue
import TuistSupport

/// `TrackableCommandInfo` contains the information to report the execution of a command
public struct TrackableCommandInfo {
    let name: String
    let subcommand: String?
    let parameters: [String: AnyCodable]
    let commandArguments: [String]
    let durationInMs: Int
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand: TrackableParametersDelegate {
    private var command: ParsableCommand
    private let clock: Clock
    private var trackedParameters: [String: AnyCodable] = [:]
    private let commandArguments: [String]
    private let commandEventFactory: CommandEventFactory
    private let asyncQueue: AsyncQueuing

    public init(
        command: ParsableCommand,
        commandArguments: [String],
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        asyncQueue: AsyncQueuing = AsyncQueue.sharedInstance
    ) {
        self.command = command
        self.commandArguments = commandArguments
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.asyncQueue = asyncQueue
    }

    func run() async throws {
        let timer = clock.startTimer()
        if let command = command as? HasTrackableParameters {
            type(of: command).analyticsDelegate = self
        }
        if var asyncCommand = command as? AsyncParsableCommand {
            try await asyncCommand.run()
        } else {
            try command.run()
        }
        let durationInSeconds = timer.stop()
        let durationInMs = Int(durationInSeconds * 1000)
        let configuration = type(of: command).configuration
        let (name, subcommand) = extractCommandName(from: configuration)
        let info = TrackableCommandInfo(
            name: name,
            subcommand: subcommand,
            parameters: trackedParameters,
            commandArguments: commandArguments,
            durationInMs: durationInMs
        )
        let commandEvent = commandEventFactory.make(from: info)
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
