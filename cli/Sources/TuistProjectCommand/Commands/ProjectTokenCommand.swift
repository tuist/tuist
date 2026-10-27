import ArgumentParser
import Foundation

public struct ProjectTokensCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
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
