import ArgumentParser
import Foundation
import TuistSupport

struct ProjectDeleteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "delete",
            _superCommandName: "project",
            abstract: "Delete a Tuist project."
        )
    }

    @Argument(
        help: "The project to delete. Must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .projectDeleteFullHandle
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectDeletePath
    )
    var path: String?

    func run() async throws {
        try await ProjectDeleteService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
