import ArgumentParser
import Foundation
import TuistNooraExtension

public enum BuildBazelStepStatus: String, ExpressibleByArgument, CaseIterable {
    case success
    case failure
    case unknown
    case localHit = "local_hit"
    case remoteHit = "remote_hit"
    case cacheHit = "cache_hit"
    case upToDate = "up_to_date"
    case skipped
    case noSource = "no_source"
}

public enum BuildBazelStepSort: String, ExpressibleByArgument, CaseIterable {
    case durationMs = "duration_ms"
    case startMs = "start_ms"
}

public struct BuildBazelStepCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "step",
            abstract: "A set of commands to inspect the actions recorded for a Bazel invocation.",
            subcommands: [
                BuildBazelStepListCommand.self,
                BuildBazelStepShowCommand.self,
            ]
        )
    }
}

public struct BuildBazelStepListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the actions recorded for a Bazel invocation, longest first."
        )
    }

    @Argument(help: "The Bazel invocation ID.")
    var invocationId: String

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

    @Option(name: .long, help: "Filter steps by status, for example failure or remote_hit.")
    var status: BuildBazelStepStatus?

    @Option(name: .long, help: "Filter steps by target label.")
    var target: String?

    @Option(name: .long, help: "Case-insensitive search across step titles, packages and targets.")
    var search: String?

    @Option(name: .long, help: "Sort by duration_ms (longest first, the default) or start_ms (earliest first).")
    var sortBy: BuildBazelStepSort?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of steps per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildBazelStepListCommandService().run(
            fullHandle: project,
            invocationId: invocationId,
            path: path,
            status: status?.rawValue,
            target: target,
            search: search,
            sortBy: sortBy?.rawValue,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct BuildBazelStepShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows a Bazel invocation step, including the log its action published."
        )
    }

    @Argument(help: "The Bazel invocation ID.")
    var invocationId: String

    @Argument(help: "The step ID returned by `tuist build bazel step list`.")
    var stepId: String

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
        try await BuildBazelStepShowCommandService().run(
            fullHandle: project,
            invocationId: invocationId,
            stepId: stepId,
            path: path,
            json: json
        )
    }
}
