import ArgumentParser
import Foundation
import TuistNooraExtension

public enum CoverageCommitsStatus: String, ExpressibleByArgument, CaseIterable {
    case measured
    case any
    case complete
    case incomplete
    case inProgress = "in_progress"
    case notMeasured = "not_measured"
}

public struct CoverageCommitsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "commits",
            _superCommandName: "coverage",
            abstract: "List a branch's commits with their coverage status, figure and change, newest first."
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

    @Option(help: "The branch whose commits to list. Defaults to the project's default branch.")
    var branch: String?

    @Option(help: "Only list commits with this status. Defaults to measured (any status but not_measured).")
    var status: CoverageCommitsStatus?

    @Option(help: "Only list commits whose SHA starts with this text.")
    var search: String?

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
        try await CoverageCommitsCommandService().run(
            path: path,
            fullHandle: fullHandle,
            branch: branch,
            status: status?.rawValue,
            search: search,
            after: after,
            before: before,
            pageSize: pageSize,
            json: json
        )
    }
}
