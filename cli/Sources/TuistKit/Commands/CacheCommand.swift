import ArgumentParser
import Foundation
import TuistSupport

/// Command to cache targets as `.(xc)framework`s and speed up your and your peers' build times.
public struct CacheCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Warms the local and remote cache."
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
        help: "Configuration to use for binary caching.",
        envKey: .cacheConfiguration
    )
    var configuration: String?

    @Argument(
        help: """
        A list of targets to cache. \
        Those and their dependant targets will be cached. \
        If no target is specified, all the project targets (excluding the external ones) and their dependencies will be cached.
        """,
        envKey: .cacheTargets
    )
    var targets: [String] = []

    @Flag(
        help: "If passed, the command doesn't cache the targets passed in the `--targets` argument, but only their dependencies",
        envKey: .cacheExternalOnly
    )
    var externalOnly: Bool = false

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips warming the cache. This is useful for debugging purposes.",
        envKey: .cacheGenerateOnly
    )
    var generateOnly: Bool = false

    @Flag(
        name: .long,
        help: "When passed, the hashes of the cacheable frameworks in the given project are printed.",
        envKey: .cachePrintHashes
    )
    var printHashes: Bool = false

    public func run() async throws {
        if printHashes {
            AlertController.current.warning(.alert(
                "The \(.command("tuist cache --print-hashes")) syntax is deprecated.",
                takeaway: "Use \(.command("tuist hash cache")) instead."
            ))
            try await HashCacheCommandService().run(
                path: path,
                configuration: configuration
            )
            return
        }

        try await Extension.cacheService.run(
            path: path,
            configuration: configuration,
            targetsToBinaryCache: Set(targets),
            externalOnly: externalOnly,
            generateOnly: generateOnly
        )
    }
}
