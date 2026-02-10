import ArgumentParser
import Foundation

struct TestCaseRunCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
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
