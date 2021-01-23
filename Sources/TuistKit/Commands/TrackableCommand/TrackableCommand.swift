import ArgumentParser
import Foundation
import TuistSupport
import TuistAsyncQueue

/// `TrackableCommandInfo` contains the information to report the execution of a command
public struct TrackableCommandInfo {
    let name: String
    let subcommand: String?
    let parameters: [String: String]
    let duration: TimeInterval
}

/// A `TrackableCommand` wraps a `ParsableCommand` and reports its execution to an analytics provider
public class TrackableCommand: TrackableParametersDelegate {
    private var command: ParsableCommand
    private let clock: Clock
    private var trackedParameters: [String: String] = [:]
    private let commandEventFactory: CommandEventFactory
    private let asyncQueue: AsyncQueuing

    public init(
        command: ParsableCommand,
        clock: Clock = WallClock(),
        commandEventFactory: CommandEventFactory = CommandEventFactory(),
        asyncQueue: AsyncQueuing = AsyncQueue.sharedInstance
    ) {
        self.command = command
        self.clock = clock
        self.commandEventFactory = commandEventFactory
        self.asyncQueue = asyncQueue
    }

    func run(completion: @escaping () -> ()) throws {
        let timer = clock.startTimer()
        if let command = command as? HasTrackableParameters {
            type(of: command).analyticsDelegate = self
        }
        try command.run()
        let duration = timer.stop()
        let configuration = type(of: command).configuration
        let (name, subcommand) = extractCommandName(from: configuration)
        let info = TrackableCommandInfo(
            name: name,
            subcommand: subcommand,
            parameters: trackedParameters,
            duration: duration
        )
        let commandEvent = commandEventFactory.make(from: info)
        asyncQueue.dispatch(event: commandEvent, completion: completion)
    }

    func willRun(withParameters parameters: [String: String]) {
        trackedParameters = parameters
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
