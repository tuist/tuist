import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct TestCaseRunListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists runs for a test case."
        )
    }

    @Argument(
        help: "The test case identifier. Either a UUID or the format Module/Suite/TestCase (or Module/TestCase).",
        envKey: .testCaseRunListIdentifier
    )
    var testCaseIdentifier: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseRunListProject
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testCaseRunListPath
    )
    var path: String?

    @Flag(
        name: .long,
        help: "Filter by flaky runs.",
        envKey: .testCaseRunListFlaky
    )
    var flaky: Bool = false

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed).",
        envKey: .testCaseRunListPage
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of runs per page. Defaults to 10.",
        envKey: .testCaseRunListPageSize
    )
    var pageSize: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseRunListJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestCaseRunListCommandService().run(
            project: project,
            path: path,
            testCaseIdentifier: testCaseIdentifier,
            flaky: flaky,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
