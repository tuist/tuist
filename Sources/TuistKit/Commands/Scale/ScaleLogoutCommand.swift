import ArgumentParser
import Foundation
import TSCBasic

struct ScaleLogoutCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "logout",
                             abstract: "Removes any existing session to authenticate on the server with the URL defined in the Config.swift file")
    }

    func run() throws {
        try ScaleLogoutService().logout()
    }
}
