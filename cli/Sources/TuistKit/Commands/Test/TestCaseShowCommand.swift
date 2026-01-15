import ArgumentParser
import Foundation
import Path
import TuistSupport

struct TestCaseShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test case.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The ID of the test case to show.",
        envKey: .testCaseShowId
    )
    var testCaseId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .testCaseShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .testCaseShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestCasesShowCommandService().run(
            project: project,
            testCaseId: testCaseId,
            path: path,
            json: json
        )
    }
}
