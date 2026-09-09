#if os(macOS)
    import ArgumentParser
    import Foundation
    import TuistEnvKey
    import TuistExtension

    public struct CachePullCommand: AsyncParsableCommand {
        public init() {}

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "pull",
                _superCommandName: "cache",
                abstract: "Pulls cached binaries for the current project graph."
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory that contains the project whose binaries will be pulled.",
            completion: .directory,
            envKey: .cachePath
        )
        var path: String?

        @Option(
            name: .shortAndLong,
            help: "Configuration to use when calculating binary cache hashes.",
            envKey: .cacheConfiguration
        )
        var configuration: String?

        @Argument(
            help: "A list of targets or target tags whose binaries, including their dependencies, will be pulled. If no target is specified, all cacheable targets are pulled.",
            envKey: .cacheTargets
        )
        var targets: [String] = []

        public func run() async throws {
            try await Extension.cachePullService.run(
                path: path,
                configuration: configuration,
                targets: Set(targets)
            )
        }
    }
#endif
