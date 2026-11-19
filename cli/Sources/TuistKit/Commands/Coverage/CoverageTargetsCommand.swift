import ArgumentParser
import Foundation
import TuistNooraExtension

public enum CoverageTargetsSortBy: String, ExpressibleByArgument, CaseIterable {
    case coverage
    case name
    case files
}

public struct CoverageTargetsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "targets",
            _superCommandName: "coverage",
            abstract: "List the coverage of a commit's targets, least covered first, then those not measured."
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

    @Option(help: "The branch whose latest complete commit to read. Defaults to the project's default branch.")
    var branch: String?

    @Option(help: "The commit to read. Takes precedence over --branch.")
    var commit: String?

    @Option(help: "Only list targets whose name contains this text.")
    var search: String?

    @Option(help: "Sort by coverage, name or files. Defaults to coverage.")
    var sortBy: CoverageTargetsSortBy?

    @Option(help: "Sort ascending (asc) or descending (desc). Defaults to asc.")
    var sortOrder: CoverageFilesSortOrder?

    @Option(help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(help: "The number of targets per page. Defaults to 20.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageTargetsCommandService().run(
            path: path,
            fullHandle: fullHandle,
            branch: branch,
            commit: commit,
            search: search,
            sortBy: sortBy?.rawValue,
            sortOrder: sortOrder?.rawValue,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
