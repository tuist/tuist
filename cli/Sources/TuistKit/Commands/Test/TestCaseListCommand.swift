import ArgumentParser
import Foundation
import Path
import TuistSupport

struct TestCaseListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all test cases stored on the server for a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .testCaseListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .testCaseListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter test cases by name.",
        envKey: .testCaseListName
    )
    var name: String?

    @Option(
        name: .long,
        help: "Filter test cases by module name.",
        envKey: .testCaseListModuleName
    )
    var moduleName: String?

    @Option(
        name: .long,
        help: "Filter test cases by suite name.",
        envKey: .testCaseListSuiteName
    )
    var suiteName: String?

    @Option(
        name: .long,
        help: "Filter test cases by last status.",
        envKey: .testCaseListStatus
    )
    var status: String?

    @Option(
        name: .long,
        help: "The page number to fetch.",
        envKey: .testCaseListPage
    )
    var page: Int?

    @Option(
        name: .customLong("per-page"),
        help: "The number of items per page.",
        envKey: .testCaseListPerPage
    )
    var perPage: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestCasesListCommandService().run(
            project: project,
            path: path,
            name: name,
            moduleName: moduleName,
            suiteName: suiteName,
            status: status,
            page: page,
            perPage: perPage,
            json: json
        )
    }
}
