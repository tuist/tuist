#if os(macOS)
    import ArgumentParser
    import Foundation
    import TuistCASAnalytics
    import TuistEnvKey
    import TuistNooraExtension

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

        var jsonThroughNoora: Bool = false

        func run() async throws {
            let database = try CASAnalyticsDatabase()
            try database.migrate()
            try await InspectBuildCommandService(casAnalyticsDatabase: database)
                .run(
                    path: path,
                    derivedDataPath: derivedDataPath
                )
        }
    }
#endif
