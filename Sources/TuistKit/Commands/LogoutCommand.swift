import ArgumentParser
import Foundation
import Path

struct LogoutCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            abstract: "Removes an existing Tuist session."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .logoutPath
    )
    var path: String?

    func run() async throws {
        try await LogoutService().logout(
            directory: path
        )
    }
}
