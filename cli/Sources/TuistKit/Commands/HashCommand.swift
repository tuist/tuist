import ArgumentParser
import Foundation
import TuistSupport

/// A command to hash an Xcode or generated project.
public struct HashCommand: AsyncParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "hash",
            abstract: "Utilities to debug the hashing logic used by features like binary caching or selective testing.",
            subcommands: [
                HashCacheCommand.self,
                HashSelectiveTestingCommand.self,
            ]
        )
    }
}
