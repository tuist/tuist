import ArgumentParser
import Foundation
import TSCBasic

struct CloudAuthCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            _superCommandName: "cloud",
            abstract: "Authenticates the user for using Cloud"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .cloudAuthPath
    )
    var path: String?

    func run() async throws {
        try await CloudAuthService().authenticate(directory: path)
    }
}
