import ArgumentParser
import Foundation

public struct CacheCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache",
            abstract: "Cache-related commands.",
            subcommands: subcommands,
            defaultSubcommand: defaultSubcommand
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [CacheWarmCommand.self, CacheConfigCommand.self]
        #else
            [CacheConfigCommand.self]
        #endif
    }

    private static var defaultSubcommand: ParsableCommand.Type? {
        #if os(macOS)
            CacheWarmCommand.self
        #else
            CacheConfigCommand.self
        #endif
    }
}
