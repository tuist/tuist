import ArgumentParser
import Foundation
import TuistNooraExtension

public struct CoverageFileCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "file",
            _superCommandName: "coverage",
            abstract: "Show the coverage of one file at a commit, with its functions."
        )
    }

    @Argument(help: "The file's path, as listed by `tuist coverage files`.")
    var filePath: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration."
    )
    var fullHandle: String?

    @Option(help: "The branch whose latest complete commit to read. Defaults to the project's default branch.")
    var branch: String?

    @Option(help: "The commit to read. Takes precedence over --branch.")
    var commit: String?

    @Flag(help: "Include per-line execution counts, and list the uncovered lines.")
    var lines: Bool = false

    @Flag(help: "The output in JSON format.")
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await CoverageFileCommandService().run(
            path: path,
            fullHandle: fullHandle,
            branch: branch,
            commit: commit,
            filePath: filePath,
            includeLines: lines,
            json: json
        )
    }
}
