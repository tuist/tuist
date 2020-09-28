import ArgumentParser
import Foundation
import TSCBasic

/// A coomand to fetch project's dependencies.
struct DependenciesFetchCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "fetch",
                             abstract: "Fetches project's dependecies ")
    }
    
    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
        completion: .directory
    )
    var path: String?
    
    func run() throws {
        try DependenciesFetchService().run(path: path)
    }
}
