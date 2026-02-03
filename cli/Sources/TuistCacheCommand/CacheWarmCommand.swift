#if os(macOS)
    import ArgumentParser
    import Foundation
    import TuistAlert
    import TuistEnvKey
    import TuistExtension
    import TuistSupport

    struct CacheWarmCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "warm",
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

        func run() async throws {
            if printHashes {
                AlertController.current.warning(.alert(
                    "The \(.command("tuist cache --print-hashes")) syntax is deprecated.",
                    takeaway: "Use \(.command("tuist hash cache")) instead."
                ))
                try await Extension.hashCacheService.run(path: path, configuration: configuration)
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
#endif
