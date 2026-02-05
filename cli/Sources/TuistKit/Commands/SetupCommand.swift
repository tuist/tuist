import ArgumentParser
import Foundation

public struct SetupCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            abstract: "Commands to set up and configure Tuist services",
            subcommands: [
                SetupCacheCommand.self,
            ]
        )
    }
}
