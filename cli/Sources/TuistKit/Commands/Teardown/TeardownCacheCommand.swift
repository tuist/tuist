import ArgumentParser
import Foundation

struct TeardownCacheCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            _superCommandName: "teardown",
            abstract: "Stop the Tuist Xcode cache daemon and remove its LaunchAgent and socket"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    func run() async throws {
        try await TeardownCacheCommandService().run(
            path: path
        )
    }
}
