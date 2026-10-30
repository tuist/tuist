import ArgumentParser
import Foundation

public struct ProjectRepositoryDisconnectCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "disconnect",
            _superCommandName: "repository",
            abstract: "Remove a project's link to its GitHub repository."
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist project.",
        completion: .directory
    )
    var path: String?

    public func run() async throws {
        try await ProjectRepositoryDisconnectService().run(fullHandle: project, path: path)
    }
}
