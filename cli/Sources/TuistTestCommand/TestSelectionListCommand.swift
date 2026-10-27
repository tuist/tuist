import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

enum SelectiveTestingHitStatus: String, ExpressibleByArgument, CaseIterable {
    case miss
    case local
    case remote
}

public struct TestXcodeTargetListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all targets for a test run."
        )
    }

    @Argument(help: "The ID of the test run.")
    var testRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter by hit status (miss, local, or remote)."
    )
    var hitStatus: SelectiveTestingHitStatus?

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed)."
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of targets per page. Defaults to 10."
    )
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestXcodeTargetListCommandService().run(
            fullHandle: project,
            testRunId: testRunId,
            path: path,
            hitStatus: hitStatus,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
