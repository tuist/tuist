import ArgumentParser
import Foundation
import TSCBasic

public struct CloudCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands to interact with the cloud.",
            subcommands: [
                CloudAuthCommand.self,
                CloudSessionCommand.self,
                CloudLogoutCommand.self,
                CloudInitCommand.self,
                CloudCleanCommand.self,
            ]
        )
    }
    
    // MARK: - Init
    
    public init() {}
}
