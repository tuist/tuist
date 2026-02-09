import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct GenerationListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all the generations in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .generationListFullHandle
    )
    var projectFullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .generationListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter generations by git branch.",
        envKey: .generationListGitBranch
    )
    var gitBranch: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .generationListJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await GenerationListCommandService().run(
            projectFullHandle: projectFullHandle,
            path: path,
            gitBranch: gitBranch,
            json: json
        )
    }
}
