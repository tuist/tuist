import ArgumentParser
import Foundation

public struct TestCaseRunCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "A set of commands to manage test case runs.",
            subcommands: [
                TestCaseRunListCommand.self,
                TestCaseRunShowCommand.self,
            ]
        )
    }
}
