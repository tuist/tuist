import Foundation
import ArgumentParser
import TuistSupport

protocol CommandRunning {
    mutating func run(completion: (TrackableCommandCompletion)) throws
}

typealias TrackableCommandCompletion = (TrackableCommandInfo) -> ()

struct TrackableCommandInfo {
    let name: String
    let subcommand: String?
    let parameters: [String: String]
    let duration: TimeInterval
}

public struct TrackableCommand: CommandRunning {
    private var command: ParsableCommand
    private let clock = WallClock()

    public init(command: ParsableCommand) {
        self.command = command
    }
    
    mutating func run(completion: TrackableCommandCompletion) throws {
        let timer = clock.startTimer()
        try command.run()
        let duration = timer.stop()
        let configuration = type(of: command).configuration

        let (name, subcommand) = extractCommandName(from: configuration)
        let info = TrackableCommandInfo (
            name: name,
            subcommand: subcommand,
            parameters: [:],
            duration: duration)
        completion(info)
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
