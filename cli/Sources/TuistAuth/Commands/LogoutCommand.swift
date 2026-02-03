import ArgumentParser
import Foundation
import TuistEnvKey

public struct LogoutCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "auth",
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

    @Option(
        name: .long,
        help: "The URL of the server. Required on Linux unless TUIST_URL environment variable is set."
    )
    var serverURL: String?

    public func run() async throws {
        try await LogoutService().logout(
            directory: path,
            serverURL: serverURL
        )
    }
}
