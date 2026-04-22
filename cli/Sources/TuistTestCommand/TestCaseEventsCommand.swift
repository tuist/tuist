import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct TestCaseEventsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "events",
            abstract: "Lists events for a test case (e.g. marked flaky, quarantined)."
        )
    }

    @Argument(
        help: "The test case identifier. Either a UUID or the format Module/Suite/TestCase (or Module/TestCase).",
        envKey: .testCaseEventsIdentifier
    )
    var testCaseIdentifier: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseEventsProject
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testCaseEventsPath
    )
    var path: String?

    @Option(
        help: "Page number for pagination.",
        envKey: .testCaseEventsPage
    )
    var page: Int?

    @Option(
        name: [.customLong("page-size")],
        help: "Number of events per page (default: 20, max: 100).",
        envKey: .testCaseEventsPageSize
    )
    var pageSize: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseEventsJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestCaseEventsCommandService().run(
            project: project,
            testCaseIdentifier: testCaseIdentifier,
            path: path,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
