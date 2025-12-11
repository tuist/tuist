import ArgumentParser
import Foundation
import TuistSupport

struct ProjectTokensCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tokens",
            _superCommandName: "project",
            abstract: "Manage Tuist project tokens.",
            shouldDisplay: false,
            subcommands: [
                ProjectTokensCreateCommand.self,
                ProjectTokensListCommand.self,
                ProjectTokensRevokeCommand.self,
            ]
        )
    }
}
