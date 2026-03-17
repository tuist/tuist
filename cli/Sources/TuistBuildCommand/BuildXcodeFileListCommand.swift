import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BuildXcodeFileListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists compiled files for a build."
        )
    }

    @Argument(help: "The ID of the build.")
    var buildId: String

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
        help: "Filter by target name."
    )
    var target: String?

    @Option(
        name: .long,
        help: "Filter by file type."
    )
    var fileType: String?

    @Option(
        name: .long,
        help: "Sort by field (compilation_duration or path)."
    )
    var sortBy: String?

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed)."
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of files per page. Defaults to 10."
    )
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildXcodeFileListCommandService().run(
            fullHandle: project,
            buildId: buildId,
            path: path,
            target: target,
            fileType: fileType,
            sortBy: sortBy,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
