import ArgumentParser
import Foundation
import TSCBasic

struct CacheCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        var subcommands: [ParsableCommand.Type] = []
        #if canImport(TuistCloud)
            subcommands = [
                CacheWarmCommand.self,
                CachePrintHashesCommand.self,
            ]
        #endif
        return CommandConfiguration(
            commandName: "cache",
            abstract: "A set of utilities related to the caching of targets.",
            subcommands: subcommands
        )
    }
}
