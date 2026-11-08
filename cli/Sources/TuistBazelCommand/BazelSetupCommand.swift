import ArgumentParser
import Foundation
import TuistEnvKey

public struct BazelSetupCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            _superCommandName: "bazel",
            abstract: "Generate a .bazelrc.tuist file that configures Bazel to use Tuist's remote cache and build insights."
        )
    }

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the directory containing the Tuist project.",
        envKey: .bazelSetupPath
    )
    var path: String?

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "Configure Bazel to send build insights through the Build Event Service."
    )
    var buildInsights = true

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "Add the generated .bazelrc.tuist import to .bazelrc."
    )
    var addBazelrcImport = true

    @Flag(
        name: .long,
        inversion: .prefixedNo,
        help: "Fetch dependencies through Kura with local fallback."
    )
    var remoteDownloader = true

    @Flag(
        name: .long,
        help: "Run Linux actions on Tuist remote executors when the account has remote execution enabled. Falls back to the remote cache alone when it is not available."
    )
    var remoteExecution = false

    public func run() async throws {
        try await BazelSetupCommandService().run(
            directory: path,
            buildInsights: buildInsights,
            remoteDownloader: remoteDownloader,
            remoteExecution: remoteExecution,
            addBazelrcImport: addBazelrcImport
        )
    }
}
