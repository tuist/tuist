import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct TestShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a test run."
        )
    }

    @Argument(
        help: "The ID of the test run to show.",
        envKey: .testShowId
    )
    var testRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .testShowProject
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .testShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testShowJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestShowCommandService().run(
            project: project,
            testRunId: testRunId,
            path: path,
            json: json
        )
    }
}
