import ArgumentParser
import Foundation
import Path
import TuistSupport

struct GenerateListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all the generations in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .generateListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .generateListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter generations by git branch.",
        envKey: .generateListGitBranch
    )
    var gitBranch: String?

    @Option(
        name: .long,
        help: "Filter generations by git commit SHA.",
        envKey: .generateListGitCommitSHA
    )
    var gitCommitSHA: String?

    @Option(
        name: .long,
        help: "Filter generations by git ref.",
        envKey: .generateListGitRef
    )
    var gitRef: String?

    @Option(
        name: .long,
        help: "The page number to fetch.",
        envKey: .generateListPage
    )
    var page: Int?

    @Option(
        name: .customLong("per-page"),
        help: "The number of items per page.",
        envKey: .generateListPerPage
    )
    var perPage: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .generateListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await GenerationsListCommandService().run(
            project: project,
            path: path,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            page: page,
            perPage: perPage,
            json: json
        )
    }
}
