import ArgumentParser
import Foundation
import TuistCore
import TuistEnvKey
import TuistSupport

public struct XcodeBuildTestCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild test extends the xcodebuild CLI test action with insights."
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
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild test -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15' -parallel-testing-enabled YES"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        let shardConfig: ShardConfiguration? = if shardMax != nil || shardMin != nil || shardTotal != nil
            || shardMaxDuration != nil
        {
            ShardConfiguration(
                shardMin: shardMin,
                shardMax: shardMax,
                shardTotal: shardTotal,
                shardMaxDuration: shardMaxDuration,
                granularity: shardGranularity == "suite" ? .suite : .module
            )
        } else {
            nil
        }

        let shardIndex: Int? = EnvKey.testShardIndex.envValue()

        try await XcodeBuildTestCommandService()
            .run(
                passthroughXcodebuildArguments: ["test"] + passthroughXcodebuildArguments,
                shardConfiguration: shardConfig,
                shardIndex: shardIndex
            )
    }
}
