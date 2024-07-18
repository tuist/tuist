import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectTokensCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tokens",
            _superCommandName: "project",
            abstract: "Manage Tuist project tokens.",
            subcommands: [
                ProjectTokensCreateCommand.self,
                ProjectTokensListCommand.self,
                ProjectTokensRevokeCommand.self,
            ]
        )
    }
}
