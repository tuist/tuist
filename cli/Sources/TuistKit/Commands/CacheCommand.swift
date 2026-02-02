import ArgumentParser
import Foundation
import TuistCacheConfigCommand

public struct CacheCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Cache-related commands.",
            subcommands: [
                CacheWarmCommand.self,
                TuistCacheConfigCommand.CacheConfigCommand.self,
            ],
            defaultSubcommand: CacheWarmCommand.self
        )
    }
}
