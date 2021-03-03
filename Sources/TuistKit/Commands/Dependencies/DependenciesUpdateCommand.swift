import ArgumentParser
import Foundation
import TSCBasic

/// A command to update project's dependencies.
struct DependenciesUpdateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            _superCommandName: "dependencies",
            abstract: "Updates the project's dependencies defined in `Dependencies.swift`."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try DependenciesUpdateService().run(path: path)
    }
}
