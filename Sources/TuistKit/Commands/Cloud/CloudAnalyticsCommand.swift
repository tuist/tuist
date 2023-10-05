#if canImport(TuistCloud)
    import ArgumentParser
    import Foundation
    import TSCBasic
    import TuistSupport

    struct CloudAnalyticsCommand: AsyncParsableCommand {
        static var configuration: CommandConfiguration {
            CommandConfiguration(
                commandName: "analytics",
                _superCommandName: "cloud",
                abstract: "Open Tuist Cloud analytics dashboard."
            )
        }

        @Option(
            name: .shortAndLong,
            help: "The path to the Tuist Cloud project.",
            completion: .directory
        )
        var path: String?

        func run() async throws {
            try await CloudAnalyticsService().run(
                path: path
            )
        }
    }
#endif
