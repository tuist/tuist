import ArgumentParser
import Foundation

public struct GenerateCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generate a project or inspect generation runs.",
            subcommands: subcommands,
            defaultSubcommand: defaultSubcommand
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [GenerateRunCommand.self, GenerationListCommand.self, GenerationShowCommand.self]
        #else
            [GenerationListCommand.self, GenerationShowCommand.self]
        #endif
    }

    private static var defaultSubcommand: ParsableCommand.Type? {
        #if os(macOS)
            GenerateRunCommand.self
        #else
            nil
        #endif
    }
}
