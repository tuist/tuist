import ArgumentParser
import Foundation
import TuistNooraExtension

public enum CoverageFilesSortBy: String, ExpressibleByArgument, CaseIterable {
    case coverage
    case path
}

public enum CoverageFilesSortOrder: String, ExpressibleByArgument, CaseIterable {
    case asc
    case desc
}

public struct CoverageFilesCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "files",
            _superCommandName: "coverage",
            abstract: "List the coverage of a commit's files, least covered first."
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

    @Option(help: "Only list files whose path contains this text.")
    var search: String?

    @Option(help: "Sort by coverage or path. Defaults to coverage.")
    var sortBy: CoverageFilesSortBy?

    @Option(help: "Sort ascending (asc) or descending (desc). Defaults to asc.")
    var sortOrder: CoverageFilesSortOrder?

    @Option(help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(help: "The number of files per page. Defaults to 20.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageFilesCommandService().run(
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
