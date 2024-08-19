import ArgumentParser
import Foundation
import Path
import TuistSupport

struct ProjectShowCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "project",
            abstract: "Show information about the specified project. Use --web flag to open the project in the browser."
        )
    }

    @Argument(
        help: "The project to show. The full handle must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .projectShowFullHandle
    )
    var fullHandle: String?

    @Flag(
        help: "Open a project in the browser.",
        envKey: .projectShowWeb
    )
    var web: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist project.",
        completion: .directory,
        envKey: .projectShowPath
    )
    var path: String?

    func run() async throws {
        try await ProjectShowService().run(
            fullHandle: fullHandle,
            web: web,
            path: path
        )
    }
}
