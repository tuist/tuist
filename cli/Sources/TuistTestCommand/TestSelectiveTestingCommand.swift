import ArgumentParser
import Foundation
import TuistNooraExtension

public struct TestSelectiveTestingCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "selective-testing",
            abstract: "A set of commands to inspect a test run's coverage-based test selection.",
            subcommands: [
                TestSelectiveTestingListCommand.self,
                TestSelectiveTestingChangedFilesCommand.self,
            ]
        )
    }
}

enum SelectiveTestingDecision: String, ExpressibleByArgument, CaseIterable {
    case selected
    case skipped
}

public struct TestSelectiveTestingListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists the tests a test run's coverage-based selection selected or skipped, and why."
        )
    }

    @Argument(help: "The ID of the test run.")
    var testRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(name: .shortAndLong, help: "The path to the directory or a subdirectory of the project.", completion: .directory)
    var path: String?

    @Option(name: .long, help: "Only list the selected or the skipped tests.")
    var decision: SelectiveTestingDecision?

    @Option(name: .long, help: "Only list the tests with this reason, such as impacted, unaffected or tracked_file_changed.")
    var reason: String?

    @Option(name: .long, help: "Only list the tests whose module, suite or name contains this text.")
    var search: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of tests per page. Defaults to 20.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestSelectiveTestingListCommandService().run(
            project: project,
            testRunId: testRunId,
            path: path,
            decision: decision?.rawValue,
            reason: reason,
            search: search,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}

public struct TestSelectiveTestingChangedFilesCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "changed-files",
            abstract: "Lists the files that changed since a test run's coverage-based selection baseline."
        )
    }

    @Argument(help: "The ID of the test run.")
    var testRunId: String

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle."
    )
    var project: String?

    @Option(name: .shortAndLong, help: "The path to the directory or a subdirectory of the project.", completion: .directory)
    var path: String?

    @Option(name: .long, help: "Only list the files whose path contains this text.")
    var search: String?

    @Option(name: .long, help: "The page number to fetch (1-indexed).")
    var page: Int?

    @Option(name: .long, help: "The number of files per page. Defaults to 20.")
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await TestSelectiveTestingFilesCommandService().run(
            project: project,
            testRunId: testRunId,
            path: path,
            search: search,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
