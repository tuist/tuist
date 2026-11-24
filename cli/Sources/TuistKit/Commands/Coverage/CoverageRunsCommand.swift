import ArgumentParser
import Foundation
import TuistNooraExtension

public struct CoverageRunsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "runs",
            _superCommandName: "coverage",
            abstract: "List the test runs with coverage behind a commit or a branch, each marked full, partial or discarded."
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

    @Option(help: "The branch whose runs to list. Defaults to the project's default branch.")
    var branch: String?

    @Option(help: "The commit whose runs to list. Takes precedence over --branch.")
    var commit: String?

    @Option(help: "Only list the runs of this scheme.")
    var scheme: String?

    @Option(help: "Read the page older than this cursor: a previous page's end cursor.")
    var after: String?

    @Option(help: "Read the page newer than this cursor: a previous page's start cursor.")
    var before: String?

    @Option(help: "The number of results per page. Defaults to 20.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageRunsCommandService().run(
            path: path,
            fullHandle: fullHandle,
            branch: branch,
            commit: commit,
            scheme: scheme,
            after: after,
            before: before,
            pageSize: pageSize,
            json: json
        )
    }
}
