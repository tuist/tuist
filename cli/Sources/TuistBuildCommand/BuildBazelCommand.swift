import ArgumentParser
import Foundation
import TuistNooraExtension

public struct BuildBazelCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bazel",
            abstract: "A set of commands to inspect Bazel invocations.",
            subcommands: [
                BuildBazelListCommand.self,
                BuildBazelShowCommand.self,
                BuildBazelStepCommand.self,
                BuildBazelLogsCommand.self,
            ]
        )
    }
}

public struct BuildBazelListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the Bazel invocations of a project, newest first."
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

    @Option(name: .long, help: "Filter invocations by git branch.")
    var gitBranch: String?

    @Option(name: .long, help: "Filter invocations by status (success or failure).")
    var status: BuildListStatus?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of invocations per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildBazelListCommandService().run(
            fullHandle: project,
            path: path,
            gitBranch: gitBranch,
            status: status?.rawValue,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct BuildBazelShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows a Bazel invocation, including its cache statistics, build metrics and critical path."
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

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildBazelShowCommandService().run(
            fullHandle: project,
            invocationId: invocationId,
            path: path,
            json: json
        )
    }
}

public struct BuildBazelLogsCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logs",
            abstract: "Prints the console output and test logs captured for a Bazel invocation, in order."
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

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildBazelLogsCommandService().run(
            fullHandle: project,
            invocationId: invocationId,
            path: path,
            json: json
        )
    }
}
