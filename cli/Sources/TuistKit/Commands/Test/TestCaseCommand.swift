import ArgumentParser
import Foundation

struct TestCaseCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "case",
            abstract: "Commands to interact with test cases stored on the server.",
            subcommands: [
                TestCaseListCommand.self,
                TestCaseShowCommand.self,
            ]
        )
    }
}
