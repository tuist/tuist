import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

struct TestCaseShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test case."
        )
    }

    @Argument(
        help: "The ID of the test case to show.",
        envKey: .testCaseShowId
    )
    var testCaseId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseShowFullHandle
    )
    var fullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
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
        try await TestCaseShowCommandService().run(
            fullHandle: fullHandle,
            testCaseId: testCaseId,
            path: path,
            json: json
        )
    }
}
