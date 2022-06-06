import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct CloudCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>
    
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands to interact with the cloud.",
            subcommands: [
                CloudAuthCommand.self,
                CloudSessionCommand.self,
                CloudLogoutCommand.self,
            ]
        )
    }
}
