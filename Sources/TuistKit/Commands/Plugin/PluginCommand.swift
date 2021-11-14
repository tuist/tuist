import ArgumentParser
import Foundation
import TSCBasic

struct PluginCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "plugin",
            abstract: "A set of commands for plugin's management.",
            subcommands: [
                PluginArchiveCommannd.self,
            ]
        )
    }
}
