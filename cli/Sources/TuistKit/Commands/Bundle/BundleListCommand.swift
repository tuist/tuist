import ArgumentParser
import Foundation
import Path
import TuistSupport

struct BundleListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all the bundles in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .bundleListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .bundleListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter bundles by git branch.",
        envKey: .bundleListGitBranch
    )
    var gitBranch: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .bundleListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await BundleListCommandService().run(
            project: project,
            path: path,
            gitBranch: gitBranch,
            json: json
        )
    }
}
