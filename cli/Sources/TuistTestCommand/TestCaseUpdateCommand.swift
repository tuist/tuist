import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension
import TuistServer

public struct TestCaseUpdateCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            abstract: "Updates a test case."
        )
    }

    @Argument(
        help: "The test case identifier. Either a UUID or the format Module/Suite/TestCase (or Module/TestCase).",
        envKey: .testCaseUpdateIdentifier
    )
    var testCaseIdentifier: String

    @Option(
        help: "The new state for the test case.",
        envKey: .testCaseUpdateState
    )
    var state: ServerTestCaseState?

    @Flag(
        inversion: .prefixedNo,
        exclusivity: .exclusive,
        help: "Mark the test case as flaky (--flaky) or not flaky (--no-flaky).",
        envKey: .testCaseUpdateFlaky
    )
    var flaky: Bool?

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testCaseUpdateProject
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testCaseUpdatePath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testCaseUpdateJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestCaseUpdateCommandService().run(
            project: project,
            testCaseIdentifier: testCaseIdentifier,
            state: state,
            isFlaky: flaky,
            path: path,
            json: json
        )
    }
}

extension ServerTestCaseState: @retroactive ExpressibleByArgument {}
