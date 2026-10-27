import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BuildXcodeCacheTaskListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists cacheable tasks for a build."
        )
    }

    @Argument(help: "The ID of the build.")
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
        help: "Filter by cache status (hit_local, hit_remote, or miss)."
    )
    var status: String?

    @Option(
        name: .long,
        help: "Filter by task type (clang or swift)."
    )
    var taskType: String?

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
        try await BuildXcodeCacheTaskListCommandService().run(
            fullHandle: project,
            buildId: buildId,
            path: path,
            status: status,
            taskType: taskType,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
