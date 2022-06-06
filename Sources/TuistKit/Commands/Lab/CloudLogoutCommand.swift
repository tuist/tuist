import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct CloudLogoutCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>
    
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "cloud",
            abstract: "Removes any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }

    func run() throws {
        try CloudLogoutService().logout()
    }
}
