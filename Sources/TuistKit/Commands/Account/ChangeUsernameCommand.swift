import ArgumentParser
import Foundation
import Path

struct ChangeUsernameCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "change-username",
            _superCommandName: "auth",
            abstract: "Change the logged in user's username."
        )
    }

    @Option(
        help: "New username.",
        envKey: .changeUsernameName
    )
    var name: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .changeUsernamePath
    )
    var path: String?

    func run() async throws {
        try await ChangeUsernameService().run(
            name: name,
            directory: path
        )
    }
}
