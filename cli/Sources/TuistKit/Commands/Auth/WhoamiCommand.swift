import ArgumentParser
import Foundation

struct WhoamiCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
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

    func run() async throws {
        try await WhoamiService().run(
            directory: path
        )
    }
}
