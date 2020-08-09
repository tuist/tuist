import ArgumentParser
import Foundation

struct GenerateWorkspaceCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "project",
            abstract: "Generates an Xcode workspace to start working on the project"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path where the project will be generated."
    )
    var path: String?

    @Flag(
        help: "Only generate the local project (without generating its dependencies)."
    )
    var projectOnly: Bool

    @Flag(help: "Generate a project replacing dependencies with pre-compiled assets.")
    var cache: Bool

    func run() throws {
        try GenerateWorkspaceService().run(
            path: path,
            projectOnly: projectOnly,
            cache: cache
        )
    }
}
