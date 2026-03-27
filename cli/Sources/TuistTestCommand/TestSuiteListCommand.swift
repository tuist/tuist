import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct TestSuiteListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists suite runs for a test run."
        )
    }

    @Argument(help: "The ID of the test run.")
    var testRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(name: .shortAndLong, help: "The path to the directory or a subdirectory of the project.", completion: .directory)
    var path: String?

    @Option(name: .long, help: "Filter by status (success or failure).")
    var status: String?

    @Option(name: .long, help: "Filter by module name.")
    var moduleName: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of suite runs per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestSuiteListCommandService().run(
            testRunId: testRunId,
            fullHandle: project,
            path: path,
            status: status,
            moduleName: moduleName,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
