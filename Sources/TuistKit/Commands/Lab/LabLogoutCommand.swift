import ArgumentParser
import Foundation
import TSCBasic

struct LabLogoutCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "lab",
            abstract: "Removes any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }

    func run() throws {
        try LabLogoutService().logout()
    }
}
