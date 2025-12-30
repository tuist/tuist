import ArgumentParser
import Foundation
import TuistSupport

struct AccountTokensCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
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
