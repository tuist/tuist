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

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    public func run() async throws {
        try await SetupCacheCommandService().run(path: path)
        try await SetupInsightsCommandService().run(path: path)
    }
}
