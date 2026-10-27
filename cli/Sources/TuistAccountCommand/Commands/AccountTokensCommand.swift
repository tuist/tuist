import ArgumentParser
import Foundation

public struct AccountTokensCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "tokens",
            _superCommandName: "account",
            abstract: "Manage Tuist account tokens.",
            subcommands: [
                AccountTokensCreateCommand.self,
                AccountTokensListCommand.self,
                AccountTokensRevokeCommand.self,
            ]
        )
    }
}
