import ArgumentParser
import Foundation

public struct BuildGradleTaskCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "task",
            abstract: "A set of commands to inspect Gradle build tasks.",
            subcommands: [
                BuildGradleTaskListCommand.self,
            ]
        )
    }
}
