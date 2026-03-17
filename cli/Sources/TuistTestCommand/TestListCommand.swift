import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct TestListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all test runs in a project."
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(name: .shortAndLong, help: "The path to the directory or a subdirectory of the project.", completion: .directory)
    var path: String?

    @Option(name: .long, help: "Filter test runs by git branch.")
    var gitBranch: String?

    @Option(name: .long, help: "Filter test runs by status (success or failure).")
    var status: String?

    @Option(name: .long, help: "Filter test runs by scheme.")
    var scheme: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of test runs per page. Defaults to 10.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestListCommandService().run(
            fullHandle: project,
            path: path,
            gitBranch: gitBranch,
            status: status,
            scheme: scheme,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
