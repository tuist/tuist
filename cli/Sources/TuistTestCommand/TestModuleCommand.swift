import ArgumentParser
import Foundation

public struct TestModuleCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "module",
            abstract: "A set of commands to manage test module runs.",
            subcommands: [TestModuleListCommand.self]
        )
    }
}
