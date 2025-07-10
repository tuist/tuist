import ArgumentParser
import Foundation
import TuistSupport

struct BundleListCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "bundle",
            abstract: "List bundles for a project."
        )
    }

    @Flag(help: "The output in JSON format.", envKey: .bundleListJson)
    var json: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .bundleListPath
    )
    var path: String?

    @Option(
        name: .customLong("git-branch"),
        help: "Filter bundles by git branch.",
        envKey: .bundleListGitBranch
    )
    var gitBranch: String?

    @Option(
        help: "Page number for pagination (starting from 1).",
        envKey: .bundleListPage
    )
    var page: Int?

    @Option(
        name: .customLong("page-size"),
        help: "Number of items per page (max 100).",
        envKey: .bundleListPageSize
    )
    var pageSize: Int?

    func run() async throws {
        try await BundleListService().run(
            json: json,
            directory: path,
            gitBranch: gitBranch,
            page: page,
            pageSize: pageSize
        )
    }
}