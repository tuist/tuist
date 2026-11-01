import ArgumentParser
import Foundation
import TuistProcess

public struct CargoCommand: AsyncParsableCommand {
    public init() {}

    public static let configuration = CommandConfiguration(
        commandName: "cargo",
        abstract: "Run Cargo with Tuist build and test insights.",
        discussion: "Cargo arguments are forwarded unchanged except Tuist shard options. Use 'test --no-run --shard-max N' to plan target-level shards, then set TUIST_SHARD_INDEX and TUIST_SHARD_PLAN_ID for 'test'. Plain tests apply mute/skip quarantine; TUIST_TEST_SKIP_QUARANTINE=1 disables it."
    )

    private static let testBuildHelp = """
    OVERVIEW: Legacy archive-based Cargo shard planning.

    USAGE: tuist cargo [+toolchain] test-build [Cargo build options] [shard options]

    This compatibility command requires a separately installed archive runner.
    For native Cargo sharding, use:
      tuist cargo test --no-run --shard-max N
    Then set TUIST_SHARD_INDEX and TUIST_SHARD_PLAN_ID for tuist cargo test.

    SHARD OPTIONS:
      --shard-total <count>              Create exactly this many shards.
      --shard-min <count>                Minimum number of shards.
      --shard-max <count>                Maximum number of shards.
      --shard-max-duration <milliseconds> Target maximum duration per shard.

    Counts must be positive. Set TUIST_PROJECT or configure a project in tuist.toml.
    Set TUIST_SHARD_REFERENCE to associate the plan with subsequent workers.
    Remaining arguments are forwarded to the archive build command.

    """

    @Argument(parsing: .unconditionalRemaining, help: "Cargo arguments, including the subcommand.")
    var arguments: [String] = []

    public static func delegatedArguments(in arguments: [String]) -> [String]? {
        let command = arguments.dropFirst().drop(while: { ["--verbose", "--quiet"].contains($0) })
        guard command.first == configuration.commandName else { return nil }
        return Array(command.dropFirst())
    }

    public func run() async throws {
        if CargoInvocation(arguments).command == "test-build",
           arguments.prefix(while: { $0 != "--" }).contains(where: { $0 == "--help" || $0 == "-h" })
        {
            FileHandle.standardOutput.write(Data(Self.testBuildHelp.utf8))
            return
        }
        do {
            try await CargoCommandService().run(arguments: arguments)
        } catch let CommandError.terminated(code, stderr, _) {
            if !["__compiler", "__native", "__script"].contains(arguments.first ?? ""), !stderr.isEmpty {
                FileHandle.standardError.write(Data(stderr.utf8))
            }
            throw ExitCode(code)
        } catch let CommandError.signalled(signal, _) {
            throw ExitCode(128 + signal)
        }
    }
}
