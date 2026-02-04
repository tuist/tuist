import ArgumentParser
import Foundation

public struct GenerateCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generate a project or inspect generation runs.",
            subcommands: [
                GenerateRunCommand.self,
                GenerationListCommand.self,
                GenerationShowCommand.self,
            ],
            defaultSubcommand: GenerateRunCommand.self
        )
    }
}
