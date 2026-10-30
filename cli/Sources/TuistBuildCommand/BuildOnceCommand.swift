import ArgumentParser
import Foundation
import TuistNooraExtension

public enum BuildOnceRunKind: String, ExpressibleByArgument, CaseIterable {
    case build
    case test
    case generic
}

public struct BuildOnceCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "once",
            abstract: "A set of commands to inspect Once runs.",
            subcommands: [
                BuildOnceListCommand.self,
                BuildOnceShowCommand.self,
            ]
        )
    }
}

public struct BuildOnceListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the Once runs of a project, newest first."
        )
    }

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

    @Option(name: .long, help: "Filter runs by kind (build, test, or generic).")
    var kind: BuildOnceRunKind?

    @Option(name: .long, help: "Filter runs by status (success or failure).")
    var status: BuildListStatus?

    @Option(name: .long, help: "Filter runs by git branch.")
    var gitBranch: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of runs per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildOnceListCommandService().run(
            fullHandle: project,
            path: path,
            kind: kind?.rawValue,
            status: status?.rawValue,
            gitBranch: gitBranch,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct BuildOnceShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows a Once run, including its actions, cache, and test totals."
        )
    }

    @Argument(help: "The ID of the Once run.")
    var runId: String

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
        try await BuildOnceShowCommandService().run(fullHandle: project, runId: runId, path: path, json: json)
    }
}
