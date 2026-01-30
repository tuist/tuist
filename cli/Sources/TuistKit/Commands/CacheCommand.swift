import ArgumentParser
import Foundation

/// Command to manage cache operations.
public struct CacheCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "A set of commands related to caching.",
            subcommands: [
                CacheWarmCommand.self,
                CacheRunListCommand.self,
                CacheRunShowCommand.self,
            ],
            defaultSubcommand: CacheWarmCommand.self
        )
    }
}
