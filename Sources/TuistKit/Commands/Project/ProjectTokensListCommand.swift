import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectTokensListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "tokens",
            abstract: "List Tuist project tokens."
        )
    }

    @Argument(
        help: "The project to list the tokens for. Must be in the format of account-handle/project-handle.",
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
        try await ProjectTokensListService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
