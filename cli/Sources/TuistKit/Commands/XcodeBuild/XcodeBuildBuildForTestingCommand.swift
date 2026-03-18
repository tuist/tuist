import ArgumentParser
import Foundation
import TuistCore
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
    var shardGranularity: String?

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild build-for-testing -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15'"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        let granularity: ShardGranularity? = if shardMax != nil || shardMin != nil || shardTotal != nil
            || shardMaxDuration != nil
        {
            shardGranularity == "suite" ? .suite : .module
        } else {
            nil
        }

        try await XcodeBuildBuildCommandService()
            .run(
                passthroughXcodebuildArguments: ["build-for-testing"] + passthroughXcodebuildArguments,
                shardGranularity: granularity,
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration
            )
    }
}
