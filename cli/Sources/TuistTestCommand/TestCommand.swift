import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project",
            discussion:
            "Use 'tuist help test run' to see options for executing tests. The 'run' subcommand is the default, so 'tuist test --clean' and 'tuist test run --clean' are equivalent.",
            subcommands: subcommands,
            defaultSubcommand: defaultSubcommand
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [
                TestRunCommand.self,
                TestShowCommand.self,
                TestListCommand.self,
                TestCaseCommand.self,
                TestModuleCommand.self,
                TestSuiteCommand.self,
                TestXcodeCommand.self,
            ]
        #else
            [
                TestShowCommand.self,
                TestListCommand.self,
                TestCaseCommand.self,
                TestModuleCommand.self,
                TestSuiteCommand.self,
                TestXcodeCommand.self,
            ]
        #endif
    }

    private static var defaultSubcommand: ParsableCommand.Type? {
        #if os(macOS)
            TestRunCommand.self
        #else
            nil
        #endif
    }
}
