import ArgumentParser
import Foundation

public struct BuildXcodeCacheTaskCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cache-task",
            abstract: "A set of commands to manage build cache tasks.",
            subcommands: [BuildXcodeCacheTaskListCommand.self]
        )
    }
}
