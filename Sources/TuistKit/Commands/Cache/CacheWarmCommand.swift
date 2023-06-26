import AnyCodable
import ArgumentParser
import Foundation
import TSCBasic
import TuistCache
import TuistSupport

/// Command to cache targets as `.(xc)framework`s and speed up your and your peers' build times.
public struct CacheWarmCommand: AsyncParsableCommand, HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate?

    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "warm",
            _superCommandName: "cache",
            abstract: "Warms the local and remote cache."
        )
    }

    @OptionGroup()
    var options: CacheOptions

    @Argument(help: """
    A list of targets to cache. \
    Those and their dependant targets will be cached. \
    If no target is specified, all the project targets (excluding the external ones) and their dependencies will be cached.
    """)
    var targets: [String] = []

    @Flag(
        help: "If passed, the command doesn't cache the targets passed in the `--targets` argument, but only their dependencies"
    )
    var dependenciesOnly: Bool = false

    public func validate() throws {
        if !options.xcframeworks, options.destination != [.device, .simulator] {
            throw ValidationError.invalidXCFrameworkOptions
        }
    }

    // MARK: - Init

    public init() {}

    // MARK: - AsyncParsableCommand

    public func run() async throws {
        try await CacheWarmService().run(
            path: options.path,
            profile: options.profile,
            xcframeworks: options.xcframeworks,
            destination: options.destination,
            targets: Set(targets),
            dependenciesOnly: dependenciesOnly
        )
        CacheWarmCommand.analyticsDelegate?.addParameters(
            [
                "xcframeworks": AnyCodable(options.xcframeworks),
                "n_targets": AnyCodable(targets.count),
                "cacheable_targets": AnyCodable(CacheAnalytics.cacheableTargets),
                "local_cache_target_hits": AnyCodable(CacheAnalytics.localCacheTargetsHits),
                "remote_cache_target_hits": AnyCodable(CacheAnalytics.remoteCacheTargetsHits),
            ]
        )
    }

    public enum ValidationError: LocalizedError {
        case invalidXCFrameworkOptions

        public var errorDescription: String? {
            switch self {
            case .invalidXCFrameworkOptions:
                return "--xcframeworks must be enabled when --destination is set"
            }
        }
    }
}
