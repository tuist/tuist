import ArgumentParser
import Foundation
import TuistNooraExtension

public struct BuildCargoCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cargo",
            abstract: "A set of commands to inspect Cargo builds.",
            subcommands: [
                BuildCargoListCommand.self,
                BuildCargoShowCommand.self,
            ]
        )
    }
}

public struct BuildCargoListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the Cargo builds of a project, newest first."
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

    @Option(name: .long, help: "Filter builds by git branch.")
    var gitBranch: String?

    @Option(name: .long, help: "Filter builds by status (success or failure).")
    var status: BuildListStatus?

    @Option(name: .long, help: "Filter builds by Cargo command, for example build or check.")
    var command: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of builds per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildCargoListCommandService().run(
            fullHandle: project,
            path: path,
            gitBranch: gitBranch,
            status: status?.rawValue,
            command: command,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct BuildCargoShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows a Cargo build, including its cache statistics."
        )
    }

    @Argument(help: "The ID of the Cargo build.")
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
        try await BuildCargoShowCommandService().run(fullHandle: project, buildId: buildId, path: path, json: json)
    }
}
