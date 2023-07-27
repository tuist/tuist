import ArgumentParser
import Foundation
import TSCBasic

struct CloudNextCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "next",
            _superCommandName: "cloud",
            abstract: "A set of commands to interact with the cloud next.",
            subcommands: [
                CloudProjectCommand.self
            ]
        )
    }
}
