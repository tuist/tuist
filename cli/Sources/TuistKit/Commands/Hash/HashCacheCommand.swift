import ArgumentParser
import Foundation
import TuistEnvKey
import TuistSupport

/// A command to hash an Xcode or generated project.
public struct HashCacheCommand: AsyncParsableCommand, ProjectPathProviding {
    public init() {}

    public static var configuration: CommandConfiguration {
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
    public var path: String?

    @Option(
        name: .shortAndLong,
        help: "The project configuration the cache binaries will be bound to.",
        envKey: .hashCacheConfiguration
    )
    var configuration: String?

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: """
        Whether the hashes are those of the instrumented variant of the binary cache. Repository-owned targets of a \
        debug configuration differ from the plain hashes; external packages and release configurations keep them. \
        Overrides `TUIST_COVERAGE_ENABLED` and `Tuist.swift`'s `coverage: .coverage(enabled:)`; omit it to follow them.
        """
    )
    var coverage: Bool?

    public func run() async throws {
        try await HashCacheCommandService().run(path: path, configuration: configuration, coverage: coverage)
    }
}
