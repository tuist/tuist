import AnyCodable
import ArgumentParser
import Foundation
import TuistCache
import TuistCore

struct GenerateCommand: AsyncParsableCommand, HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate?

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates an Xcode workspace to start working on the project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the project.",
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
        name: [.customShort("x"), .long],
        help: "When passed it uses xcframeworks (simulator and device) from the cache instead of frameworks (only simulator)."
    )
    var xcframeworks: Bool = false

    @Option(
        name: [.long],
        help: "Type of cached xcframeworks to use when --xcframeworks is passed (device/simulator)",
        completion: .list(["device", "simulator"])
    )
    var destination: CacheXCFrameworkDestination = [.device, .simulator]

    @Option(
        name: [.customShort("P"), .long],
        help: "The name of the cache profile to be used when focusing on the target."
    )
    var profile: String?

    @Flag(
        name: [.customLong("no-cache")],
        help: "Ignore cached targets, and use their sources instead."
    )
    var ignoreCache: Bool = false

    func validate() throws {
        if !xcframeworks, destination != [.device, .simulator] {
            throw ValidationError.invalidXCFrameworkOptions
        }
    }

    func run() async throws {
        try await GenerateService().run(
            path: path,
            sources: Set(sources),
            noOpen: noOpen,
            xcframeworks: xcframeworks,
            destination: destination,
            profile: profile,
            ignoreCache: ignoreCache
        )
        GenerateCommand.analyticsDelegate?.addParameters(
            [
                "no_open": AnyCodable(noOpen),
                "xcframeworks": AnyCodable(xcframeworks),
                "no_cache": AnyCodable(ignoreCache),
                "n_targets": AnyCodable(sources.count),
                "cacheable_targets": AnyCodable(CacheAnalytics.cacheableTargets),
                "local_cache_target_hits": AnyCodable(CacheAnalytics.localCacheTargetsHits),
                "remote_cache_target_hits": AnyCodable(CacheAnalytics.remoteCacheTargetsHits),
            ]
        )
    }

    enum ValidationError: LocalizedError {
        case invalidXCFrameworkOptions

        var errorDescription: String? {
            switch self {
            case .invalidXCFrameworkOptions:
                return "--xcframeworks must be enabled when --destination is set"
            }
        }
    }
}
