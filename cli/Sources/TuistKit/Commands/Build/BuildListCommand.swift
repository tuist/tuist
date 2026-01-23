import ArgumentParser
import Foundation
import Path
import TuistSupport

struct BuildListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all builds in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .buildListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .buildListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter builds by status.",
        envKey: .buildListStatus
    )
    var status: String?

    @Option(
        name: .long,
        help: "Filter builds by category.",
        envKey: .buildListCategory
    )
    var category: String?

    @Option(
        name: .long,
        help: "Filter builds by scheme.",
        envKey: .buildListScheme
    )
    var scheme: String?

    @Option(
        name: .long,
        help: "Filter builds by configuration.",
        envKey: .buildListConfiguration
    )
    var configuration: String?

    @Option(
        name: .long,
        help: "Filter builds by git branch.",
        envKey: .buildListGitBranch
    )
    var gitBranch: String?

    @Option(
        name: .long,
        help: "Filter builds by git commit SHA.",
        envKey: .buildListGitCommitSHA
    )
    var gitCommitSHA: String?

    @Option(
        name: .long,
        help: "Filter builds by git ref.",
        envKey: .buildListGitRef
    )
    var gitRef: String?

    @Option(
        name: .long,
        help: "The page number to fetch.",
        envKey: .buildListPage
    )
    var page: Int?

    @Option(
        name: .customLong("per-page"),
        help: "The number of items per page.",
        envKey: .buildListPerPage
    )
    var perPage: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .buildListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await BuildsListCommandService().run(
            project: project,
            path: path,
            status: status,
            category: category,
            scheme: scheme,
            configuration: configuration,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            page: page,
            perPage: perPage,
            json: json
        )
    }
}
