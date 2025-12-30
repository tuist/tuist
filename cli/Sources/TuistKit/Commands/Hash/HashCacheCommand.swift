import ArgumentParser
import Foundation
import TuistSupport

/// A command to hash an Xcode or generated project.
struct HashCacheCommand: AsyncParsableCommand {
    init() {}

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            _superCommandName: "hash",
            abstract: "Returns the hashes that will be used to persist binaries of the graph in its current state to the cache."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory,
        envKey: .hashCachePath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The project configuration the cache binaries will be bound to.",
        envKey: .hashCacheConfiguration
    )
    var configuration: String?

    func run() async throws {
        try await HashCacheCommandService().run(path: path, configuration: configuration)
    }
}
