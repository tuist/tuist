import ArgumentParser
import Foundation
import Path
import TuistEnvKey
import TuistNooraExtension

public struct BuildShowCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a build."
        )
    }

    @Argument(
        help: "The ID of the build to show.",
        envKey: .buildShowId
    )
    var buildId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .buildShowFullHandle
    )
    var fullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .buildShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .buildShowJson
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildShowCommandService().run(
            fullHandle: fullHandle,
            buildId: buildId,
            path: path,
            json: json
        )
    }
}
