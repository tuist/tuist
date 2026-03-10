import ArgumentParser
import Foundation

struct SetupInsightsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "insights",
            _superCommandName: "setup",
            abstract: "Set up the insights daemon to gain access to richer data, such as machine metrics for build insights"
        )
    }

    func run() async throws {
        try await SetupInsightsCommandService().run()
    }
}
