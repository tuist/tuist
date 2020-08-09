import ArgumentParser
import Foundation

struct GenerateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates an Xcode workspace to start working on the project or generate individual project components defined in subcommands",
            subcommands: [
                GenerateWorkspaceCommand.self,
                NamespaceCommand.self,
            ],
            defaultSubcommand: GenerateWorkspaceCommand.self
        )
    }
}
