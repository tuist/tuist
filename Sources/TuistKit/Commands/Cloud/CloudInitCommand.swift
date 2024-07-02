import ArgumentParser
import Foundation
import Path
import TuistSupport

struct CloudInitCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init",
            _superCommandName: "cloud",
            abstract: "Creates a new tuist cloud project."
        )
    }

    @Argument(
        help: "The project to initialize the Tuist project with. Must be in the format of account-handle/project-handle.",
        completion: .directory,
        envKey: .cloudInitName
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudInitPath
    )
    var path: String?

    func run() async throws {
        try await CloudInitService().createProject(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
