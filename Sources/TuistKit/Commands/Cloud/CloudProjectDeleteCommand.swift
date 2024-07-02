import ArgumentParser
import Foundation
import TuistSupport

struct CloudProjectDeleteCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "delete",
            _superCommandName: "project",
            abstract: "Delete a Cloud project."
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
        envKey: .cloudProjectDeletePath
    )
    var path: String?

    func run() async throws {
        try await CloudProjectDeleteService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
