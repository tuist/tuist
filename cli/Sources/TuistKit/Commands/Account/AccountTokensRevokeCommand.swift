import ArgumentParser
import Foundation
import TuistSupport

struct AccountTokensRevokeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "revoke",
            _superCommandName: "tokens",
            abstract: "Revoke a Tuist account token."
        )
    }

    @Argument(
        help: "The account handle to revoke the token for.",
        envKey: .accountTokensAccountHandle
    )
    var accountHandle: String

    @Argument(
        help: "The name of the token to revoke.",
        envKey: .accountTokensName
    )
    var name: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .accountTokensPath
    )
    var path: String?

    func run() async throws {
        try await AccountTokensRevokeCommandService().run(
            accountHandle: accountHandle,
            tokenName: name,
            path: path
        )
    }
}
