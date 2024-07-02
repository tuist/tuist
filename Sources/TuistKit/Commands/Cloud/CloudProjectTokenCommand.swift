import ArgumentParser
import Foundation
import Path
import TuistSupport

struct CloudProjectTokenCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "token",
            _superCommandName: "project",
            abstract: "Get a project token. You can save this token in the `TUIST_CONFIG_CLOUD_TOKEN` environment variable to use the remote cache on the CI."
        )
    }

    @Argument(
        help: "The project to get the token for. Must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .cloudProjectTokenProjectName
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudProjectTokenPath
    )
    var path: String?

    func run() async throws {
        try await CloudProjectTokenService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
