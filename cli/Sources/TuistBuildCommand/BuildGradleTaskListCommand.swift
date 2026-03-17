import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BuildGradleTaskListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all tasks for a Gradle build."
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

    @Option(
        name: .long,
        help: "Filter tasks by outcome (local_hit, remote_hit, up_to_date, executed, failed, skipped, no_source)."
    )
    var outcome: String?

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed)."
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of tasks per page. Defaults to 10."
    )
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildGradleTaskListCommandService().run(
            fullHandle: project,
            buildId: buildId,
            path: path,
            outcome: outcome,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
