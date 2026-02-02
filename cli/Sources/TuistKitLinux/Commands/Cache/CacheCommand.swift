import ArgumentParser
import Foundation

struct CacheCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Cache management commands.",
            subcommands: [
                CacheConfigCommand.self,
            ],
            defaultSubcommand: CacheConfigCommand.self
        )
    }
}
