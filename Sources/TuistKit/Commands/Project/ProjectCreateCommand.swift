import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectCreateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "project",
            abstract: "Create a new project."
        )
    }

    @Argument(
        help: "The project to create. The full handle must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .projectCreateFullHandle
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectCreatePath
    )
    var path: String?

    func run() async throws {
        try await ProjectCreateService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
