import ArgumentParser
import Foundation

public struct BuildCacheTaskCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache-task",
            abstract: "A set of commands to manage build cache tasks.",
            subcommands: [BuildCacheTaskListCommand.self]
        )
    }
}
