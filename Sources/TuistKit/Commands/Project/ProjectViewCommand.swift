import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectViewCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "view",
            _superCommandName: "project",
            abstract: "Open the project dashboard in the system default's browser."
        )
    }

    @Argument(
        help: "The project to view. The full handle must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .projectViewFullHandle
    )
    var fullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist project",
        completion: .directory,
        envKey: .projectViewPath
    )
    var path: String?

    func run() async throws {
        try await ProjectViewService().run(fullHandle: fullHandle, path: path)
    }
}
