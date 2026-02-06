import ArgumentParser
import Foundation
import Path
import TuistNooraExtension
import TuistSupport

enum BuildListStatus: String, ExpressibleByArgument, CaseIterable {
    case success
    case failure
}

struct BuildListCommand: AsyncParsableCommand, NooraReadyCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists all builds in a project."
        )
    }

    @Option(
        name: [.customLong("project"), .customShort("P")],
        help: "The full handle of the project. Must be in the format of account-handle/project-handle.",
        envKey: .buildListFullHandle
    )
    var fullHandle: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .buildListPath
    )
    var path: String?

    @Option(
        name: .long,
        help: "Filter builds by git branch.",
        envKey: .buildListGitBranch
    )
    var gitBranch: String?

    @Option(
        name: .long,
        help: "Filter builds by status (success or failure).",
        envKey: .buildListStatus
    )
    var status: BuildListStatus?

    @Option(
        name: .long,
        help: "Filter builds by scheme.",
        envKey: .buildListScheme
    )
    var scheme: String?

    @Option(
        name: .long,
        help: "Filter builds by configuration.",
        envKey: .buildListConfiguration
    )
    var configuration: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Filter builds by tags. Returns builds containing ALL specified tags."
    )
    var tags: [String] = []

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help: "Filter builds by custom values (key=value format). Returns builds matching ALL specified values."
    )
    var values: [String] = []

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed).",
        envKey: .buildListPage
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of builds per page. Defaults to 10.",
        envKey: .buildListPageSize
    )
    var pageSize: Int?

    @Flag(
        help: "The output in JSON format.",
        envKey: .buildListJson
    )
    var json: Bool = false

    var jsonThroughNoora: Bool = true

    func run() async throws {
        try await BuildListCommandService().run(
            fullHandle: fullHandle,
            path: path,
            gitBranch: gitBranch,
            status: status?.rawValue,
            scheme: scheme,
            configuration: configuration,
            tags: tags,
            values: values,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
