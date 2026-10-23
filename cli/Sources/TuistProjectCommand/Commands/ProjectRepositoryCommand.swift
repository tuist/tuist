import ArgumentParser
import Foundation

public struct ProjectRepositoryCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "repository",
            _superCommandName: "project",
            abstract: "Manage the GitHub repository a Tuist project is linked to.",
            subcommands: [
                ProjectRepositoryConnectCommand.self,
                ProjectRepositoryDisconnectCommand.self,
            ]
        )
    }
}
