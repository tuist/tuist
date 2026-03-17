import ArgumentParser
import Foundation

public struct BuildXcodeIssueCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "issue",
            abstract: "A set of commands to manage build issues.",
            subcommands: [BuildXcodeIssueListCommand.self]
        )
    }
}
