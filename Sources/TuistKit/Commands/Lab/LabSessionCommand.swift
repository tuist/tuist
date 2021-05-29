import ArgumentParser
import Foundation
import TSCBasic

struct LabSessionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "session",
            _superCommandName: "lab",
            abstract: "Prints any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }

    func run() throws {
        try LabSessionService().printSession()
    }
}
