import ArgumentParser
import Foundation
import TSCBasic

enum FetchCategory: String, CaseIterable, RawRepresentable, ExpressibleByArgument {
    case dependencies
    case plugins
}

/// A command to fetch any remote content necessary to interact with the project.
struct FetchCommand: AsyncParsableCommand {
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

    @Flag(
        name: .shortAndLong,
        help: "Instead of simple fetch, update external content when available."
    )
    var update: Bool = false

    func runAsync() async throws {
        try await FetchService().run(
            path: path,
            update: update
        )
    }
}
