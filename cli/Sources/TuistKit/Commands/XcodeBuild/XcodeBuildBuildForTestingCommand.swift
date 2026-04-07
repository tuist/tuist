import ArgumentParser
import Foundation
import TuistCore
import TuistEnvironment
import TuistEnvKey
import TuistSupport
import XcodeGraph

public struct XcodeBuildBuildForTestingCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build-for-testing",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild build-for-testing extends the xcodebuild CLI build-for-testing action with insights."
        )
    }

    public var analyticsRequired: Bool { true }

    public init() {}

    @Option(
        name: .long,
        help: "Maximum number of shards to distribute tests across.",
        envKey: .testShardMax
    )
    var shardMax: Int?

    @Option(
        name: .long,
        help: "Minimum number of shards.",
        envKey: .testShardMin
    )
    var shardMin: Int?

    @Option(
        name: .long,
        help: "Exact number of shards (mutually exclusive with --shard-min/--shard-max).",
        envKey: .testShardTotal
    )
    var shardTotal: Int?

    @Option(
        name: .long,
        help: "Target maximum duration per shard in milliseconds.",
        envKey: .testShardMaxDuration
    )
    var shardMaxDuration: Int?

    @Option(
        name: .long,
        help: "Sharding granularity level: module (default) or suite.",
        envKey: .testShardGranularity
    )
    var shardGranularity: ShardGranularity = .module

    @Option(
        name: .long,
        help: "Explicit shard reference. Derived from environment variables for supported CI providers.",
        envKey: .testShardReference
    )
    var shardReference: String?

    @Flag(
        name: .long,
        help: "Skip uploading test products to remote storage. Use when you provide test products to shard runners yourself, for example via shared volumes.",
        envKey: .testShardSkipUpload
    )
    var shardSkipUpload: Bool = false

    @Option(
        name: .long,
        help: "Path where Tuist should write the optimized shard archive instead of uploading test products to remote storage.",
        completion: .file(),
        envKey: .testShardArchivePath
    )
    var shardArchivePath: String?

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild build-for-testing -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15'"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        let shardArchivePath = try await { () async throws -> AbsolutePath? in
            if let shardArchivePath = self.shardArchivePath {
                return try await Environment.current.pathRelativeToWorkingDirectory(shardArchivePath)
            }
            return nil
        }()
        try await XcodeBuildBuildCommandService()
            .run(
                passthroughXcodebuildArguments: ["build-for-testing"] + passthroughXcodebuildArguments,
                shardReference: shardReference,
                shardGranularity: shardGranularity,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                shardSkipUpload: shardSkipUpload,
                shardArchivePath: shardArchivePath
            )
    }
}
