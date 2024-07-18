import ArgumentParser
import Foundation
import Path
import TuistSupport

struct AnalyticsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "analytics",
            abstract: "Open the Tuist analytics dashboard."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist project.",
        completion: .directory,
        envKey: .analyticsPath
    )
    var path: String?

    func run() async throws {
        try await AnalyticsService().run(
            path: path
        )
    }
}
