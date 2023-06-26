import ArgumentParser
import Foundation
import TSCBasic

public struct EncryptCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "encrypt",
            _superCommandName: "signing",
            abstract: "Encrypts all files in Tuist/Signing directory"
        )
    }
    
    // MARK: - Arguments and Flags

    @Option(
        name: .shortAndLong,
        help: "The path to the folder containing the certificates you would like to encrypt",
        completion: .directory
    )
    var path: String?
    
    // MARK: - Init
    
    public init() {}

    // MARK: - ParsableCommand
    
    public func run() throws {
        try EncryptService().run(path: path)
    }
}
