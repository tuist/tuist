import ArgumentParser
import Foundation
import TuistSupport

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
    private let commandEventTagger: CommandEventTagging
    private var trackedParameters: [String: String] = [:]

    public init(
        command: ParsableCommand,
        commandEventTagger: CommandEventTagging = CommandEventTagger(),
        clock: Clock = WallClock()
    ) {
        self.command = command
        self.clock = clock
        self.commandEventTagger = commandEventTagger
    }

    func run() throws {
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
        commandEventTagger.tagCommand(from: info)
    }

    func willRun(withParamters parameters: [String: String]) {
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
