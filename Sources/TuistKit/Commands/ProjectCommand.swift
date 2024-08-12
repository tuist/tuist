import ArgumentParser
import Foundation
import Path

struct ProjectCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "project",
            abstract: "A set of commands to manage your Tuist projects.",
            subcommands: [
                ProjectShowCommand.self,
                ProjectCreateCommand.self,
                ProjectListCommand.self,
                ProjectDeleteCommand.self,
                ProjectTokensCommand.self,
                ProjectUpdateCommand.self,
            ]
        )
    }
}
