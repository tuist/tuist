import ArgumentParser
import Foundation
import TuistSupport

/// A command to hash an Xcode or generated project.
struct HashCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "hash",
            abstract: "Obtains and returns the hashes of a project modules."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory,
        envKey: .cachePath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "When obtaining the hashes for caching, the project configuration that binaries will be bound to.",
        envKey: .cacheConfiguration
    )
    var configuration: String?

    public func run() async throws {
        try await CachePrintHashesService().run(path: path, configuration: configuration)
    }
}
