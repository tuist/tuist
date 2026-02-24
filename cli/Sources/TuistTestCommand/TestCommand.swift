import ArgumentParser
import Foundation

public struct TestCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a project",
            subcommands: subcommands,
            defaultSubcommand: defaultSubcommand
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [TestRunCommand.self, TestShowCommand.self, TestCaseCommand.self]
        #else
            [TestShowCommand.self, TestCaseCommand.self]
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
