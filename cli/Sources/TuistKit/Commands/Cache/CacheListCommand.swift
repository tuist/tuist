import ArgumentParser
import Foundation
import Path
import TuistSupport

struct CacheListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all cache runs in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .cacheListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .cacheListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter cache runs by git branch.",
        envKey: .cacheListGitBranch
    )
    var gitBranch: String?

    @Option(
        name: .long,
        help: "Filter cache runs by git commit SHA.",
        envKey: .cacheListGitCommitSHA
    )
    var gitCommitSHA: String?

    @Option(
        name: .long,
        help: "Filter cache runs by git ref.",
        envKey: .cacheListGitRef
    )
    var gitRef: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .cacheListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await CacheRunsListCommandService().run(
            project: project,
            path: path,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            json: json
        )
    }
}
