import ArgumentParser
import Foundation
import TuistEnvKey

public struct ProjectTokensCreateCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "tokens",
            abstract: "Create a new Tuist project token. You can save this token in the `TUIST_TOKEN` environment variable to authenticate requests against the Tuist API.",
            shouldDisplay: false
        )
    }

    @Argument(
        help: "The project to create the token for. Must be in the format of account-handle/project-handle.",
        envKey: .projectTokenFullHandle
    )
    var fullHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .projectTokenPath
    )
    var path: String?

    public func run() async throws {
        try await ProjectTokensCreateService().run(
            fullHandle: fullHandle,
            directory: path
        )
    }
}
