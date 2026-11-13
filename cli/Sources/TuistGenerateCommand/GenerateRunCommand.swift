#if os(macOS)
    import ArgumentParser
    import Foundation
    import Path
    import TuistAlert
    import TuistConfig
    import TuistConstants
    import TuistCore
    import TuistEnvironment
    import TuistExtension
    import TuistKit
    import TuistLogging
    import TuistServer
    import TuistSupport

    public struct GenerateRunCommand: AsyncParsableCommand, ProjectPathProviding {
        public init() {}

        public static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "run",
                _superCommandName: "generate",
                abstract: "Generates an Xcode workspace to start working on the project.",
                discussion:
                "Use 'tuist generate list' and 'tuist generate show' to inspect generation runs. Pass --quiet to suppress generation progress output. Warnings and errors may still be reported."
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory or a subdirectory of the project.",
            completion: .directory,
            envKey: .generatePath
        )
        public var path: String?

        @Argument(
            help: ArgumentHelp(
                """
                Targets to focus on, specified by name or tag query (e.g. 'tag:feature'). \
                Other targets will be linked as binaries if possible. \
                If no target is specified, all the project targets will be generated (except external ones, such as Swift packages).
                """,
                valueName: "query"
            )
        )
        var includedTargets: [TargetQuery] = []

        @Flag(
            name: .shortAndLong,
            help: "Don't open the project after generating it.",
            envKey: .generateOpen
        )
        var open: Bool = !Environment.current.isCI

        @Flag(
            help: "Ignore binary cache and use sources only.",
            envKey: .generateBinaryCache
        )
        var binaryCache: Bool = true

        @Option(
            name: .long,
            help:
            "Binary cache profile to use: \(BaseCacheProfile.allCases.map(\.rawValue).joined(separator: ", ")), or a custom profile name. Defaults to the profile configured in Tuist.swift, or 'only-external' if not configured.",
            envKey: .generateCacheProfile
        )
        var cacheProfile: CacheProfileType?

        @Option(
            name: .shortAndLong,
            help: "Configuration to generate for."
        )
        var configuration: String?

        @Option(name: .long, help: "Destinations to generate: all, simulator, or device. Native macOS targets remain supported.")
        var destination: CacheDestination = .all

        public func run() async throws {
            let isQuiet = MachineReadableOutput.isQuiet(arguments: Environment.current.arguments)
                || Environment.current.variables[Constants.EnvironmentVariables.quiet] != nil
            try await Logger.$current.withValue(Self.generationLogger(Logger.current, isQuiet: isQuiet)) {
                try await generate()
            }
        }

        static func generationLogger(_ logger: Logger, isQuiet: Bool) -> Logger {
            var logger = logger
            if isQuiet {
                logger.logLevel = max(logger.logLevel, .warning)
            }
            return logger
        }

        private func generate() async throws {
            if !binaryCache {
                AlertController.current.warning(.alert(
                    "The \(.command("--no-binary-cache")) flag is deprecated.",
                    takeaway: "Use \(.command("--cache-profile none")) instead."
                ))
            }

            try await GenerateService(
                cacheStorageFactory: Extension.cacheStorageFactory,
                generatorFactory: Extension.generatorFactory
            ).run(
                path: path,
                includedTargets: Set(includedTargets),
                noOpen: !open,
                configuration: configuration,
                ignoreBinaryCache: !binaryCache,
                cacheProfile: cacheProfile,
                destination: destination
            )
        }
    }
#endif
