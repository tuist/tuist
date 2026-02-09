import ArgumentParser
import Foundation

public struct TestCaseCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "case",
            abstract: "A set of commands to manage test cases.",
            subcommands: [
                TestCaseListCommand.self,
            ]
        )
    }
}
