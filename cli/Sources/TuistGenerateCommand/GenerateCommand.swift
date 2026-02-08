import ArgumentParser
import Foundation

public struct GenerateCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generate a project or inspect generation runs.",
            subcommands: [GenerationListCommand.self, GenerationShowCommand.self]
        )
    }
}
