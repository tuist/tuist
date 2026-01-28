import ArgumentParser
import Foundation
import Path
import TuistSupport

struct CacheRunShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a cache run.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The ID of the cache run to show.",
        envKey: .cacheRunShowId
    )
    var cacheRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .cacheRunShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .cacheRunShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .cacheRunShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await CacheRunShowCommandService().run(
            project: project,
            cacheRunId: cacheRunId,
            path: path,
            json: json
        )
    }
}
