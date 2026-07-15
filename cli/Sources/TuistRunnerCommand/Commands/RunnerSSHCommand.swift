import ArgumentParser
import Foundation
import TuistEnvKey
import TuistNooraExtension

public struct RunnerSSHCommand: AsyncParsableCommand, NooraReadyCommand {
    public var jsonThroughNoora: Bool { false }

    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "ssh",
            _superCommandName: "runner",
            abstract: "Open a shell for a running job.",
            discussion: """
            Pass either a Tuist runner job URL or the GitHub Actions workflow job ID.
            The job ID identifies the specific runner job, not the workflow run.

            Examples:
              tuist runner ssh 87303732349
              tuist runner ssh https://tuist.dev/tuist/runners/runs/29385019740/jobs/87256360989
            """
        )
    }

    @Argument(
        help: "A runner job URL or job ID.",
        envKey: .runnerSSHJobRef
    )
    var jobRef: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .runnerSSHPath
    )
    var path: String?

    public func run() async throws {
        try await RunnerSSHCommandService().run(jobRef: jobRef, path: path)
    }
}
