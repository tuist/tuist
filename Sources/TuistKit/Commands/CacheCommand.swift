import ArgumentParser
import Foundation
import TSCBasic

struct CacheCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "scale",
                             abstract: "A set of utilities related to the caching of targets.", subcommands: [
                                 CacheWarmCommand.self,
                                 CachePrintHashesCommand.self,
                             ])
    }
}
