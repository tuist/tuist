import ArgumentParser
import Foundation
import Path

struct ProjectUpdateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            _superCommandName: "project",
            abstract: "Update project settings"
        )
    }

    @Argument(
        help: "The full handle of the project to update. Must be in the format of account-handle/project-handle."
    )
    var fullHandle: String?

    @Option(
        help: "Set the default branch name for the repository linked to the project."
    )
    var defaultBranch: String?

    @Option(
        help: "Set the connected Git repository. Example: --repository-url https://github.com/tuist/tuist"
    )
    var repositoryURL: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await ProjectUpdateService()
            .run(
                fullHandle: fullHandle,
                defaultBranch: defaultBranch,
                repositoryURL: repositoryURL,
                path: path
            )
    }
}
