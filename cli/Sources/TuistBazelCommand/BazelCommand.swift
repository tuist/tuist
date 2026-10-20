import ArgumentParser
import Foundation

public struct BazelCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bazel",
            abstract: "Integrate Bazel with Tuist's remote cache, build insights, and test quarantine.",
            shouldDisplay: false,
            subcommands: [
                BazelSetupCommand.self,
                BazelTestCommand.self,
                BazelCredentialHelperCommand.self,
            ]
        )
    }
}
