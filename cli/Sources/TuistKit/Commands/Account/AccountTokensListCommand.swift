import ArgumentParser
import Foundation
import TuistSupport

struct AccountTokensListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "tokens",
            abstract: "List Tuist account tokens."
        )
    }

    @Argument(
        help: "The account handle to list the tokens for.",
        envKey: .accountTokensAccountHandle
    )
    var accountHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .accountTokensPath
    )
    var path: String?

    func run() async throws {
        try await AccountTokensListCommandService().run(
            accountHandle: accountHandle,
            path: path
        )
    }
}
