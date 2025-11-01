import ArgumentParser
import Foundation
import TuistServer

struct ProjectUpdateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            _superCommandName: "project",
            abstract: "Update project settings"
        )
    }

    @Argument(
        help:
        "The full handle of the project to update. Must be in the format of account-handle/project-handle."
    )
    var fullHandle: String?

    @Option(
        help: "Set the default branch name for the repository linked to the project."
    )
    var defaultBranch: String?

    @Option(
        help:
        "Set the project's visibility. When private, only project's members have access to the project. Public projects are accessible by anyone."
    )
    var visibility: ServerProject.Visibility?

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
                visibility: visibility,
                path: path
            )
    }
}

extension ServerProject.Visibility: @retroactive ExpressibleByArgument {}
