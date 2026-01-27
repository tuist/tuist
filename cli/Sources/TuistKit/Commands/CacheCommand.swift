import ArgumentParser
import Foundation

/// Command to manage cache operations.
public struct CacheCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Cache-related commands.",
            subcommands: [
                CacheWarmCommand.self,
                CacheRunListCommand.self,
                CacheRunShowCommand.self,
                CacheConfigCommand.self,
            ],
            defaultSubcommand: CacheWarmCommand.self
        )
    }
}
