import ArgumentParser
import Foundation

public struct CacheCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Cache-related commands.",
            subcommands: [
                CacheWarmCommand.self,
                CacheConfigCommand.self,
            ],
            defaultSubcommand: CacheWarmCommand.self
        )
    }
}
