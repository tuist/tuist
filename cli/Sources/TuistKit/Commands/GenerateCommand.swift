import ArgumentParser
import Foundation

public struct GenerateCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "A set of commands related to project generation.",
            subcommands: [
                GenerateRunCommand.self,
                GenerationListCommand.self,
                GenerationShowCommand.self,
            ],
            defaultSubcommand: GenerateRunCommand.self
        )
    }
}
