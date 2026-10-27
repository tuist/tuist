import ArgumentParser
import Foundation

struct TeardownInsightsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "insights",
            _superCommandName: "teardown",
            abstract: "Stop the insights daemon and remove its LaunchAgent and sampled machine metrics"
        )
    }

    func run() async throws {
        try await TeardownInsightsCommandService().run()
    }
}
