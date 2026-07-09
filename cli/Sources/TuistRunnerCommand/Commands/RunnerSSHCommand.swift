import ArgumentParser
import Foundation
import TuistEnvKey

public struct RunnerSSHCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "ssh",
            _superCommandName: "runner",
            abstract: "Open a shell on a running Tuist runner job."
        )
    }

    @Argument(
        help: "A runner job URL or workflow job ID.",
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
