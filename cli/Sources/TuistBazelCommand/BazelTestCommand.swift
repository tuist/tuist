import ArgumentParser
import Command
import Foundation

public struct BazelTestCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Run Bazel tests with Tuist's test quarantine policies.",
            discussion: "Skipped cases exclude their entire Bazel target. Muted cases run and only their reported failures are ignored. Pass Bazel arguments after '--'."
        )
    }

    @Option(name: [.customShort("p"), .long], help: "The path to the Tuist project and Bazel working directory.")
    var path: String?

    @Option(name: .long, help: "The Bazel executable to run.")
    var bazel = "bazel"

    @Flag(name: .long, inversion: .prefixedNo, help: "Apply Tuist's skipped and muted test states.")
    var quarantine = true

    @Argument(parsing: .remaining, help: "Arguments forwarded to 'bazel test', including target patterns.")
    var arguments: [String] = []

    public func run() async throws {
        do {
            try await BazelTestCommandService().run(
                directory: path,
                bazel: bazel,
                arguments: arguments,
                quarantine: quarantine
            )
        } catch let CommandError.terminated(code, _, _) {
            throw ExitCode(code)
        }
    }
}
