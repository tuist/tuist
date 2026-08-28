import ArgumentParser
import Foundation

public struct BazelInvokeCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "invoke",
            _superCommandName: "bazel",
            abstract: "Run Bazel and send its completed invocation, test results, and output directly to Tuist."
        )
    }

    @Option(name: [.customShort("p"), .long], help: "The path to the directory containing the Tuist project.")
    var path: String?

    @Argument(parsing: .captureForPassthrough, help: "The Bazel command and arguments to run.")
    var arguments: [String]

    public func run() async throws {
        try await BazelInvokeCommandService().run(arguments: arguments, directory: path)
    }
}
