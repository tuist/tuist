import ArgumentParser
import Foundation

public struct RunnerCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "runner",
            abstract: "Interact with Tuist runners.",
            subcommands: [
                RunnerSSHCommand.self,
            ]
        )
    }
}
