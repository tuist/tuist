import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

struct TestCaseRunShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test case run."
        )
    }

    @Argument(
        help: "The ID of the test case run to show.",
        envKey: .testCaseRunShowId
    )
    var testCaseRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseRunShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testCaseRunShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseRunShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestCaseRunShowCommandService().run(
            project: project,
            testCaseRunId: testCaseRunId,
            path: path,
            json: json
        )
    }
}
