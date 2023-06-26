import ArgumentParser
import Foundation
import TSCBasic

public struct CloudLogoutCommand: ParsableCommand {
    
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "logout",
            _superCommandName: "cloud",
            abstract: "Removes any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }
    
    // MARK: - Init
    
    public init() {}

    // MARK: - Run
    
    public func run() throws {
        try CloudLogoutService().logout()
    }
}
