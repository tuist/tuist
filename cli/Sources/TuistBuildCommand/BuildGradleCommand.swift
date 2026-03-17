import ArgumentParser
import Foundation

public struct BuildGradleCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "gradle",
            abstract: "A set of commands to inspect Gradle build details.",
            subcommands: [
                BuildGradleTaskCommand.self,
            ]
        )
    }
}
