import ArgumentParser
import Foundation
import TSCBasic

/// A command to clean project's dependencies.
struct DependenciesCleanCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            _superCommandName: "dependencies",
            abstract: "Cleans the project's dependencies."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try DependenciesCleanService().run(path: path)
    }
}
