import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistServer
import TuistSupport

/// Command to cache targets as `.(xc)framework`s and speed up your and your peers' build times.
public struct CacheCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}

    public var runId = ""
    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var analyticsDelegate: TrackableParametersDelegate?
    public static var cacheService: CacheServicing = EmptyCacheService()

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Warms the local and remote cache."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "Configuration to use for binary caching."
    )
    var configuration: String?

    @Argument(help: """
    A list of targets to cache. \
    Those and their dependant targets will be cached. \
    If no target is specified, all the project targets (excluding the external ones) and their dependencies will be cached.
    """)
    var targets: [String] = []

    @Flag(
        help: "If passed, the command doesn't cache the targets passed in the `--targets` argument, but only their dependencies"
    )
    var externalOnly: Bool = false

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips warming the cache. This is useful for debugging purposes."
    )
    var generateOnly: Bool = false

    @Flag(
        name: .long,
        help: "When passed, the hashes of the cacheable frameworks in the given project are printed."
    )
    var printHashes: Bool = false

    public func run() async throws {
        if printHashes {
            try await CachePrintHashesService(
                generatorFactory: Self.generatorFactory
            ).run(
                path: path,
                configuration: configuration
            )
            return
        }

        try await Self.cacheService.run(
            path: path,
            configuration: configuration,
            targetsToBinaryCache: Set(targets),
            externalOnly: externalOnly,
            generateOnly: generateOnly
        )
        CacheCommand.analyticsDelegate?.addParameters(
            [
                "n_targets": AnyCodable(targets.count),
                "cacheable_targets": AnyCodable(CacheAnalyticsStore.shared.cacheableTargets),
                "local_cache_target_hits": AnyCodable(CacheAnalyticsStore.shared.localCacheTargetsHits),
                "remote_cache_target_hits": AnyCodable(CacheAnalyticsStore.shared.remoteCacheTargetsHits),
                "test_targets": AnyCodable(CacheAnalyticsStore.shared.testTargets),
                "local_test_target_hits": AnyCodable(CacheAnalyticsStore.shared.localTestTargetHits),
                "remote_test_target_hits": AnyCodable(CacheAnalyticsStore.shared.remoteTestTargetHits),
            ]
        )
    }
}
