import ArgumentParser
import Foundation

struct SetupCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "setup",
            abstract: "Commands to set up and configure Tuist services",
            subcommands: [
                SetupCacheCommand.self,
            ]
        )
    }
}
