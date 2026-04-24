import ArgumentParser
import Foundation
import Path
import TuistEnvironment
import TuistEnvKey
import TuistSupport

public struct XcodeBuildTestWithoutBuildingCommand: AsyncParsableCommand, TrackableParsableCommand,
    RecentPathRememberableCommand
{
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test-without-building",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild test-without-building extends the xcodebuild CLI test action with insights."
        )
    }

    public var analyticsRequired: Bool { true }

    public init() {}

    @Flag(
        name: .long,
        help: "When passed, the quarantine feature is disabled and tests run regardless of whether they are quarantined on the server."
    )
    public var skipQuarantine: Bool = false

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild test-without-building -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15' -testConfiguration Debug"
    )
    public var passthroughXcodebuildArguments: [String] = []

    @Option(name: .long, help: "The zero-based shard index to execute.")
    var shardIndex: Int?

    @Option(
        name: .long,
        help: "Path to a locally managed shard archive. Tuist extracts this archive instead of downloading test products from remote storage.",
        completion: .file(),
        envKey: .testShardArchivePath
    )
    var shardArchivePath: String?

    @Option(
        name: .long,
        help: "Inspect mode: 'local' parses the xcresult on this machine, 'remote' uploads it for server-side processing, 'off' skips test analysis entirely (no xcresult parsing, archiving, or upload — the Tests dashboard is not populated). When omitted, defaults to 'remote' for tuist-hosted instances and 'local' for self-hosted ones.",
        envKey: .inspectTestMode
    )
    var inspectMode: TestProcessingMode?

    public func run() async throws {
        let shardArchivePath = try await { () async throws -> AbsolutePath? in
            if let shardArchivePath = self.shardArchivePath {
                return try await Environment.current.pathRelativeToWorkingDirectory(shardArchivePath)
            }
            return nil
        }()
        try await XcodeBuildTestCommandService()
            .run(
                passthroughXcodebuildArguments: ["test-without-building"] + passthroughXcodebuildArguments,
                skipQuarantine: skipQuarantine,
                shardIndex: shardIndex ?? EnvKey.testShardIndex.envValue(),
                shardArchivePath: shardArchivePath,
                mode: inspectMode
            )
    }
}
