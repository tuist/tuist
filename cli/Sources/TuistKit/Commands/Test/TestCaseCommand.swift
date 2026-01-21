import ArgumentParser
import Foundation

struct TestCaseCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "case",
            abstract: "A set of commands to manage test cases.",
            subcommands: [
                TestCaseListCommand.self,
            ]
        )
    }
}
