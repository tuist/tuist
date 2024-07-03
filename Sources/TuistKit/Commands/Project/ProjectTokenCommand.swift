import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectTokenCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "token",
            _superCommandName: "project",
            abstract: "Get a project token. You can save this token in the `TUIST_CONFIG_TOKEN` environment variable to use the remote cache on the CI."
        )
    }

    @Argument(
        help: "The project to get the token for. Must be in the format of account-handle/project-handle.",
        completion: .directory,
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
        try await ProjectTokenService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
