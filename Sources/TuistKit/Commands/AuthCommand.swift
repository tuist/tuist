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
        help: "Email to authenticate with.",
        envKey: .authEmail
    )
    var email: String?

    @Option(
        help: "Password to authenticate with.",
        envKey: .authPassword
    )
    var password: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .authPath
    )
    var path: String?

    func run() async throws {
        try await AuthService().authenticate(
            email: email,
            password: password,
            directory: path
        )
    }
}
