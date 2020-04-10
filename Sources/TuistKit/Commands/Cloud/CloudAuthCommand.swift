import Basic
import Foundation
import ArgumentParser

struct CloudAuthCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "auth",
                             abstract: "Authenticates the user on the server with the URL defined in the Config.swift file")
    }

    func run() throws {
        try CloudAuthService().authenticate()
    }
}
