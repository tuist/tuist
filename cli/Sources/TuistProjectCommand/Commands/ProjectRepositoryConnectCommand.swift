import ArgumentParser
import Foundation

public struct ProjectRepositoryConnectCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "connect",
            _superCommandName: "repository",
            abstract: "Link a project to a GitHub repository the account's GitHub App installation can access."
        )
    }

    @Argument(
        help: "The repository's full handle, in the format owner/name."
    )
    var repository: String

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
        try await ProjectRepositoryConnectService().run(
            repository: repository,
            fullHandle: project,
            path: path
        )
    }
}
