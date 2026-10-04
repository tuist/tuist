import ArgumentParser
import Foundation
import TuistSupport

/// Tells the server that every test run gathering coverage for a commit has reported. Meant for
/// the last job of a CI pipeline, the one that depends on every test job: the commit's coverage
/// is then complete, it chains into its branch's trend, and the pull request's `tuist/coverage`
/// check, pending until now, gets its verdict.
public struct CoverageCompleteCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "complete",
            _superCommandName: "coverage",
            abstract: "Signal that the coverage pipeline of a commit has finished, so its coverage is complete and its gates can be judged."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory containing the Tuist project.",
        completion: .directory,
        envKey: .coverageCompletePath
    )
    var path: String?

    @Option(
        help: "The full handle of the project (account-handle/project-handle). Defaults to the one in the project's configuration.",
        envKey: .coverageCompleteFullHandle
    )
    var fullHandle: String?

    @Option(
        help: "The commit whose coverage pipeline finished. Defaults to the checkout's HEAD, or the commit the CI provider reports.",
        envKey: .coverageCompleteCommit
    )
    var commit: String?

    @Flag(help: "Print the commit's coverage as JSON.", envKey: .coverageCompleteJSON)
    var json: Bool = false

    public func run() async throws {
        try await CoverageCompleteCommandService().run(
            path: path,
            fullHandle: fullHandle,
            commit: commit,
            json: json
        )
    }
}
