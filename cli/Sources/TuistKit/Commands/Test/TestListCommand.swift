import ArgumentParser
import Foundation
import Path
import TuistSupport

struct TestListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all test runs in a project.",
            helpNames: [.long, .short]
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle. If not provided, it will be read from the project's Tuist.swift.",
        envKey: .testListFullHandle
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        envKey: .testListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter test runs by status.",
        envKey: .testListStatus
    )
    var status: String?

    @Option(
        name: .long,
        help: "Filter test runs by scheme.",
        envKey: .testListScheme
    )
    var scheme: String?

    @Option(
        name: .long,
        help: "Filter test runs by git branch.",
        envKey: .testListGitBranch
    )
    var gitBranch: String?

    @Option(
        name: .long,
        help: "Filter test runs by git commit SHA.",
        envKey: .testListGitCommitSHA
    )
    var gitCommitSHA: String?

    @Option(
        name: .long,
        help: "Filter test runs by git ref.",
        envKey: .testListGitRef
    )
    var gitRef: String?

    @Flag(
        help: "The output in JSON format.",
        envKey: .testListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await TestsListCommandService().run(
            project: project,
            path: path,
            status: status,
            scheme: scheme,
            gitBranch: gitBranch,
            gitCommitSHA: gitCommitSHA,
            gitRef: gitRef,
            json: json
        )
    }
}
