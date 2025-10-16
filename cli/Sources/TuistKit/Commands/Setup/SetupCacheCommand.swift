import ArgumentParser
import Foundation

struct SetupCacheCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            _superCommandName: "setup",
            abstract: "Set up the Tuist Xcode cache"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await SetupCacheCommandService().run(
            path: path
        )
    }
}
