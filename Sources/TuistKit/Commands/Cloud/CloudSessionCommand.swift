import ArgumentParser
import Foundation
import TSCBasic

public struct CloudSessionCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "session",
            _superCommandName: "cloud",
            abstract: "Prints any existing session to authenticate on the server with the URL defined in the Config.swift file"
        )
    }

    // MARK: - Init
    
    public init() {}
    
    // MARK: - ParseableCommand
    
    public func run() throws {
        try CloudSessionService().printSession()
    }
}
