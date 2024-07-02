import ArgumentParser
import Foundation
import Path

struct ProjectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "project",
            abstract: "A set of commands to manage your Tuist projects.",
            subcommands: [
                ProjectCreateCommand.self,
                ProjectListCommand.self,
                ProjectDeleteCommand.self,
                ProjectTokenCommand.self,
            ]
        )
    }
}
