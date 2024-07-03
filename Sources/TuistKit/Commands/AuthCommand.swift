import ArgumentParser
import Foundation
import Path

struct AuthCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            abstract: "Authenticates the user"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .authPath
    )
    var path: String?

    func run() async throws {
        try await AuthService().authenticate(directory: path)
    }
}
