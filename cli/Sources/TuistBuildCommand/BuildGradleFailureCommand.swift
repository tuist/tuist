import ArgumentParser
import Foundation

public struct BuildGradleFailureCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "failure",
            abstract: "A set of commands to inspect why a Gradle build failed.",
            subcommands: [
                BuildGradleFailureListCommand.self,
            ]
        )
    }
}
