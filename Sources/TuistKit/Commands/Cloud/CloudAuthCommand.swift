import ArgumentParser
import Foundation
import TSCBasic

public struct CloudAuthCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "auth",
            _superCommandName: "cloud",
            abstract: "Authenticates the user on the server with the URL defined in the Config.swift file"
        )
    }
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - ParsableCommand

    public func run() throws {
        try CloudAuthService().authenticate()
    }
}
