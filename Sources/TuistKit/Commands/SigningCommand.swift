import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct SigningCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>
    
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "signing",
            abstract: "A set of commands for signing-related operations",
            subcommands: [
                EncryptCommand.self,
                DecryptCommand.self,
            ]
        )
    }
}
