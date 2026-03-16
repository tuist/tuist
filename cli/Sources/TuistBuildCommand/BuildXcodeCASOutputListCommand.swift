import ArgumentParser
import Foundation
import Path
import TuistNooraExtension

public struct BuildXcodeCASOutputListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            abstract: "Lists CAS outputs for a build."
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
        help: "Filter by operation (download or upload)."
    )
    var operation: String?

    @Option(
        name: .long,
        help: "Filter by output type (e.g. swift, object, swiftmodule, dSYM, llvm-bc)."
    )
    var outputType: String?

    @Option(
        name: .long,
        help: "The page number to fetch (1-indexed)."
    )
    var page: Int?

    @Option(
        name: .long,
        help: "The number of outputs per page. Defaults to 10."
    )
    var pageSize: Int?

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await BuildXcodeCASOutputListCommandService().run(
            fullHandle: project,
            buildId: buildId,
            path: path,
            operation: operation,
            outputType: outputType,
            page: page,
            pageSize: pageSize,
            json: json
        )
    }
}
