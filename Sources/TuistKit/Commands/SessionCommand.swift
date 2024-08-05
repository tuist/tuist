import ArgumentParser
import Foundation
import Path

struct SessionCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "session",
            abstract: "Prints the current Tuist session"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .sessionPath
    )
    var path: String?

    func run() async throws {
        try await SessionService().printSession(
            directory: path
        )
    }
}
