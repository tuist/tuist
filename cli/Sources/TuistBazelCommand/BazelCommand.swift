import ArgumentParser
import Foundation

public struct BazelCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bazel",
            abstract: "A set of commands to integrate Bazel with Tuist's remote cache and build insights.",
            shouldDisplay: false,
            subcommands: [
                BazelSetupCommand.self,
                BazelInvokeCommand.self,
                BazelCredentialHelperCommand.self,
            ]
        )
    }
}
