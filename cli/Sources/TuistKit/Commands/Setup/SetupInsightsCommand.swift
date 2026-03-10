import ArgumentParser
import Foundation

struct SetupInsightsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "insights",
            _superCommandName: "setup",
            abstract: "Set up the Tuist machine metrics daemon for insights"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await SetupInsightsCommandService().run(
            path: path
        )
    }
}
