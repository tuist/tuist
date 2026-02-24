import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct GenerationShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a generation.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The ID of the generation to show.",
        envKey: .generationShowId
    )
    var generationId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .generationShowFullHandle
    )
    var projectFullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .generationShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .generationShowJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await GenerationShowCommandService().run(
            projectFullHandle: projectFullHandle,
            generationId: generationId,
            path: path,
            json: json
        )
    }
}
