import ArgumentParser
import Foundation

/// Commands around the code coverage a project's test runs gather.
public struct CoverageCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "coverage",
            abstract: "Utilities for the code coverage gathered by test runs.",
            subcommands: [CoverageCompleteCommand.self]
        )
    }
}
