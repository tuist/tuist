import ArgumentParser
import Foundation
import Path
import TuistSupport

struct TestShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test run.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The ID of the test run to show.",
        envKey: .testShowId
    )
    var testId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .testShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .testShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestsShowCommandService().run(
            project: project,
            testId: testId,
            path: path,
            json: json
        )
    }
}
