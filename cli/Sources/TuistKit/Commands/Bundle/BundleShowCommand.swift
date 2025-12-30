import ArgumentParser
import Foundation
import Path
import TuistSupport

struct BundleShowCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "show",
            abstract: "Shows information about a bundle.",
            helpNames: [.long, .short]
        )
    }

    @Argument(
        help: "The ID of the bundle to show.",
        envKey: .bundleShowId
    )
    var bundleId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .bundleShowFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .bundleShowPath
    )
    var path: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .bundleShowJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await BundleShowCommandService().run(
            project: project,
            bundleId: bundleId,
            path: path,
            json: json
        )
    }
}
