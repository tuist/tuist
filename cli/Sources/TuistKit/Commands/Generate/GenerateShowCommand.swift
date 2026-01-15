import ArgumentParser
import Foundation
import Path
import TuistSupport

struct GenerateShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows details for a generate run.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The generate run id.",
        envKey: .generateShowId
    )
    var runId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .generateShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .generateShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .generateShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await GenerationsShowCommandService().run(
            project: project,
            runId: runId,
            path: path,
            json: json
        )
    }
}
