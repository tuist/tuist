import ArgumentParser
import Foundation
import TSCBasic

struct PluginsCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "plugins",
            abstract: "A set of commands for plugins' management.",
            subcommands: [
                PluginsArchiveCommannd.self,
            ]
        )
    }
}
