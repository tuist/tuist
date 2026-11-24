import ArgumentParser
import Foundation
import Path
import TuistEnvironment
import TuistEnvKey
import TuistSupport

public struct XcodeBuildTestWithoutBuildingCommand: AsyncParsableCommand, TrackableParsableCommand,
    XcodeBuildPassthroughCommand
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

    var xcodebuildActionIndex: Int = 0

    @Option(name: .long, help: "The zero-based shard index to execute.")
    var shardIndex: Int?

    @Option(
        name: .long,
        help: "Explicit shard reference. Derived from environment variables for supported CI providers.",
        envKey: .testShardReference
    )
    var shardReference: String?

    @Option(
        name: .long,
        help: "Exact shard plan identifier emitted by the build-for-testing job.",
        envKey: .testShardPlanId
    )
    var shardPlanId: String?

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

    @Flag(
        inversion: .prefixedNo,
        help: "Export the images your SwiftUI previews render with the tuist/snapshots library (TEST_RUNNER_SNAPSHOTS_EXPORT_DIR) and upload them to Tuist after the run, which compares them with their baseline and fails the run when they changed and nobody approved the changes. On by default in CI for projects connected to Tuist; a run that renders no images uploads nothing. Pass --snapshots to also upload from a local run, or --no-snapshots to turn it off.",
        envKey: .testSnapshots
    )
    var snapshots: Bool?

    @Option(
        name: .long,
        help: "The snapshot set the uploaded snapshot images belong to, such as 'ios-iphone': builds are compared within a set. Defaults to the scheme.",
        envKey: .testSnapshotSet
    )
    var snapshotSet: String?

    public func run() async throws {
        let shardArchivePath = try await { () async throws -> AbsolutePath? in
            if let shardArchivePath = self.shardArchivePath {
                return try await Environment.current.pathRelativeToWorkingDirectory(shardArchivePath)
            }
            return nil
        }()
        try await XcodeBuildTestCommandService()
            .run(
                passthroughXcodebuildArguments: xcodebuildArguments,
                skipQuarantine: skipQuarantine,
                shardIndex: shardIndex ?? EnvKey.testShardIndex.envValue(),
                shardReference: shardReference,
                shardPlanId: shardPlanId,
                shardArchivePath: shardArchivePath,
                mode: inspectMode,
                snapshots: snapshots ?? EnvKey.testSnapshots.envValue(),
                snapshotSet: snapshotSet
            )
    }
}
