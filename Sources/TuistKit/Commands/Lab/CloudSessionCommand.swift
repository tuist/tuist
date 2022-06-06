import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct CloudSessionCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>
    
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "session",
            _superCommandName: "cloud",
            abstract: "Prints any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }

    func run() throws {
        try CloudSessionService().printSession()
    }
}
