import ArgumentParser
import Foundation
import TSCBasic

/// A command to fetch any remote content necessary to interact with the project.
struct FetchCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "fetch",
            abstract: "Fetches any remote content necessary to interact with the project."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try FetchService().run(path: path)
    }
}
