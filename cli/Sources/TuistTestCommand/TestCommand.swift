import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project",
            subcommands: [TestCaseCommand.self]
        )
    }
}
