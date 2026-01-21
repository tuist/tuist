import ArgumentParser
import Foundation
import Path
import TuistSupport

struct TestCaseListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists test cases for a project."
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testCaseListPath
    )
    var path: String?

    @Flag(
        name: .long,
        help: "Filter by quarantined test cases.",
        envKey: .testCaseListQuarantined
    )
    var quarantined: Bool = false

    @Flag(
        name: .long,
        help: "Filter by flaky test cases.",
        envKey: .testCaseListFlaky
    )
    var flaky: Bool = false

    @Flag(
        name: .long,
        help: "Output only test identifiers as a comma-separated list for use with xcodebuild's -only-testing option.",
        envKey: .testCaseListIdentifiersOnly
    )
    var identifiersOnly: Bool = false

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed).",
        envKey: .testCaseListPage
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of test cases per page. Defaults to 10.",
        envKey: .testCaseListPageSize
    )
    var pageSize: Int = 10

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestCaseListCommandService().run(
            project: project,
            path: path,
            quarantined: quarantined,
            flaky: flaky,
            identifiersOnly: identifiersOnly,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
