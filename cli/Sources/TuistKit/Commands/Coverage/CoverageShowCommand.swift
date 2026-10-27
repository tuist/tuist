import ArgumentParser
import Foundation
import TuistNooraExtension

public struct CoverageShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            _superCommandName: "coverage",
            abstract: "Show the coverage of a commit, or of a branch's latest complete commit."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration."
    )
    var fullHandle: String?

    @Option(help: "The branch whose latest complete commit to show. Defaults to the project's default branch.")
    var branch: String?

    @Option(help: "The commit to show. Takes precedence over --branch.")
    var commit: String?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageShowCommandService().run(
            path: path,
            fullHandle: fullHandle,
            branch: branch,
            commit: commit,
            json: json
        )
    }
}
