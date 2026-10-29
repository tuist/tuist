import ArgumentParser
import Foundation
import TuistNooraExtension

public struct BuildMixCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "mix",
            abstract: "A set of commands to inspect Mix builds.",
            subcommands: [
                BuildMixListCommand.self,
                BuildMixShowCommand.self,
            ]
        )
    }
}

public struct BuildMixListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the Mix builds of a project, newest first."
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

    @Option(name: .long, help: "Filter builds by Mix environment, for example dev or test.")
    var mixEnv: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of builds per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildMixListCommandService().run(
            fullHandle: project,
            path: path,
            gitBranch: gitBranch,
            status: status?.rawValue,
            mixEnv: mixEnv,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct BuildMixShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows a Mix build, including its cache statistics."
        )
    }

    @Argument(help: "The ID of the Mix build.")
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
        try await BuildMixShowCommandService().run(fullHandle: project, buildId: buildId, path: path, json: json)
    }
}
