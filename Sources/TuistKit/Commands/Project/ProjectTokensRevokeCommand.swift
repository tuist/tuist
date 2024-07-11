import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectTokensRevokeCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "revoke",
            _superCommandName: "tokens",
            abstract: "Revoke Tuist project tokens."
        )
    }

    @Argument(
        help: "The ID of the project token to revoke.",
        envKey: .projectTokenId
    )
    var projectTokenId: String

    @Argument(
        help: "The project to revoke the token for. Must be in the format of account-handle/project-handle.",
        envKey: .projectTokenFullHandle
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectTokenPath
    )
    var path: String?

    func run() async throws {
        try await ProjectTokensRevokeService().run(
            projectTokenId: projectTokenId,
            fullHandle: fullHandle,
            directory: path
        )
    }
}
