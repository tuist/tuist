import ArgumentParser
import Foundation
import TSCBasic

public struct SigningCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "signing",
            abstract: "A set of commands for signing-related operations",
            subcommands: [
                EncryptCommand.self,
                DecryptCommand.self,
            ]
        )
    }
    
    // MARK: - Init
    
    public init() {}
}
