import Foundation
import ArgumentParser

struct CICommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "ci",
            abstract: "A set of commands to interact with Tuist CI.",
            subcommands: [
                CIRunCommand.self,
            ]
        )
    }
}
