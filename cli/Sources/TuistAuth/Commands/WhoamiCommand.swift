import ArgumentParser
import Foundation
import TuistEnvKey

public struct WhoamiCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "whoami",
            _superCommandName: "auth",
            abstract: "Display the user's email identity currently authenticated and in use."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .whoamiPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "The URL of the server. Required on Linux unless TUIST_URL environment variable is set."
    )
    var serverURL: String?

    public func run() async throws {
        try await WhoamiService().run(
            directory: path,
            serverURL: serverURL
        )
    }
}
