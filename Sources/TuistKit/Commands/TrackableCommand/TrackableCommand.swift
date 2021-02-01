import ArgumentParser
import Combine
import Foundation
import TuistAsyncQueue
import TuistSupport

/// `TrackableCommandInfo` contains the information to report the execution of a command
public struct TrackableCommandInfo {
    let name: String
    let subcommand: String?
    let parameters: [String: String]
    let durationInMs: Int
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

    func run() throws -> Future<Void, Never> {
        let timer = clock.startTimer()
        if let command = command as? HasTrackableParameters {
            type(of: command).analyticsDelegate = self
        }
        try command.run()
        let durationInSeconds = timer.stop()
        let durationInMs = Int(durationInSeconds * 1000)
        let configuration = type(of: command).configuration
        let (name, subcommand) = extractCommandName(from: configuration)
        let info = TrackableCommandInfo(
            name: name,
            subcommand: subcommand,
            parameters: trackedParameters,
            durationInMs: durationInMs
        )
        let commandEvent = commandEventFactory.make(from: info)
        return Future { promise in
            self.asyncQueue.dispatch(event: commandEvent) {
                promise(.success(()))
            }
        }
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
