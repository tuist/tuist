import ArgumentParser
import Foundation
import TSCBasic

/// A command to fetch project's dependencies.
struct DependenciesFetchCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "fetch",
                             abstract: "Fetches the project's dependencies defined in `Dependencies.swift`.")
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try DependenciesService().run(path: path, method: .fetch)
    }
}
