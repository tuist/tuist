import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct TestCaseShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test case."
        )
    }

    @Argument(
        help: "The test case identifier. Either a UUID or the format Module/Suite/TestCase (or Module/TestCase).",
        envKey: .testCaseShowIdentifier
    )
    var testCaseIdentifier: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseShowProject
    )
    var project: String?

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

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestCaseShowCommandService().run(
            project: project,
            testCaseIdentifier: testCaseIdentifier,
            path: path,
            json: json
        )
    }
}
