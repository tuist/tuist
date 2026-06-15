import ArgumentParser
import Foundation

public struct BazelCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bazel",
            abstract: "A set of commands to integrate Bazel with the Tuist remote cache.",
            shouldDisplay: false,
            subcommands: [
                BazelSetupCommand.self,
                BazelCredentialHelperCommand.self,
            ]
        )
    }
}
