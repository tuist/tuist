import AnyCodable
import ArgumentParser
import Foundation
import TuistCore
import TuistServer
import TuistSupport

public struct GenerateCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}

    public static var analyticsDelegate: TrackableParametersDelegate?
    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()
    public var runId = ""

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates an Xcode workspace to start working on the project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Argument(help: """
    A list of targets to focus on. \
    Other targets will be linked as binaries if possible. \
    If no target is specified, all the project targets will be generated (except external ones, such as Swift packages).
    """)
    var sources: [String] = []

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it."
    )
    var noOpen: Bool = false

    @Flag(
        name: [.customLong("no-binary-cache")],
        help: "Ignore binary cache and use sources only."
    )
    var ignoreBinaryCache: Bool = false

    @Option(
        name: .shortAndLong,
        help: "Configuration to generate for."
    )
    var configuration: String?

    public func run() async throws {
        defer {
            GenerateCommand.analyticsDelegate?.addParameters(
                [
                    "no_open": AnyCodable(noOpen),
                    "no_binary_cache": AnyCodable(ignoreBinaryCache),
                    "n_targets": AnyCodable(sources.count),
                    "cacheable_targets": AnyCodable(CacheAnalyticsStore.shared.cacheableTargets),
                    "local_cache_target_hits": AnyCodable(CacheAnalyticsStore.shared.localCacheTargetsHits),
                    "remote_cache_target_hits": AnyCodable(CacheAnalyticsStore.shared.remoteCacheTargetsHits),
                    "test_targets": AnyCodable(CacheAnalyticsStore.shared.testTargets),
                    "local_test_target_hits": AnyCodable(CacheAnalyticsStore.shared.localTestTargetHits),
                    "remote_test_target_hits": AnyCodable(CacheAnalyticsStore.shared.remoteTestTargetHits),
                ]
            )
        }
        try await GenerateService(
            cacheStorageFactory: Self.cacheStorageFactory,
            generatorFactory: Self.generatorFactory
        ).run(
            path: path,
            sources: Set(sources),
            noOpen: noOpen,
            configuration: configuration,
            ignoreBinaryCache: ignoreBinaryCache
        )
    }
}
