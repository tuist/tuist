import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BuildGradleFailureListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the failed tasks and configuration steps of a Gradle build with their failure messages."
        )
    }

    @Argument(help: "The ID of the Gradle build.")
    var buildId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildGradleFailureListCommandService().run(
            fullHandle: project,
            buildId: buildId,
            path: path,
            json: json
        )
    }
}
