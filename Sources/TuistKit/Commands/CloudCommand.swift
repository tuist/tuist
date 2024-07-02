import ArgumentParser
import Foundation
import Path

struct Command: ParsableCommand {
    static var configuration: CommandConfiguration {
        var subcommands: [ParsableCommand.Type] = []
        subcommands = [
        ]
        return CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands to interact with the cloud.",
            subcommands: subcommands
        )
    }
}
