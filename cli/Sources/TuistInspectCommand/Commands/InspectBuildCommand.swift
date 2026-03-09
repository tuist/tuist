#if os(macOS)
    import ArgumentParser
    import Foundation
    import TuistEnvKey
    import TuistNooraExtension

    public enum InspectBuildMode: String, ExpressibleByArgument, CaseIterable, Sendable {
        case local
        case remote
    }

    struct InspectBuildCommand: AsyncParsableCommand, NooraReadyCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "build",
                abstract: "Inspects the latest build."
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the directory that contains the project to inspect the latest build for.",
            completion: .directory,
            envKey: .inspectBuildPath
        )
        var path: String?

        @Option(
            name: .long,
            help: "The path to the directory containing the project's derived data artifacts.",
            completion: .directory,
            envKey: .inspectBuildDerivedDataPath
        )
        var derivedDataPath: String?

        @Option(
            wrappedValue: .local,
            name: .long,
            help: "The processing mode for xcactivitylog parsing. 'remote' uploads the raw log for server-side processing. 'local' parses the log on this machine.",
            envKey: .inspectBuildMode
        )
        var mode: InspectBuildMode

        var jsonThroughNoora: Bool = false

        func run() async throws {
            try await InspectBuildCommandService()
                .run(
                    path: path,
                    derivedDataPath: derivedDataPath,
                    mode: mode
                )
        }
    }
#endif
