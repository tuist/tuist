import ArgumentParser
import Foundation

public struct TestSuiteCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "suite",
            abstract: "A set of commands to manage test suite runs.",
            subcommands: [TestSuiteListCommand.self]
        )
    }
}
