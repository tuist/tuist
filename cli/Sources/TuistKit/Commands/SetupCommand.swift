import ArgumentParser
import Foundation

public struct SetupCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            abstract: "Commands to set up and configure Tuist services",
            subcommands: [
                SetupCacheCommand.self,
                SetupInsightsCommand.self,
            ]
        )
    }

    public func run() async throws {
        try await SetupCacheCommandService().run(path: nil)
        try await SetupInsightsCommandService().run()
    }
}
