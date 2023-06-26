import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

public struct CloudCleanCommand: AsyncParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "clean",
            _superCommandName: "cloud",
            abstract: "Cleans the remote cache."
        )
    }

    // MARK: - Flags and Arguments
    
    @Option(
        name: .shortAndLong,
        help: "The path to the Tuist Cloud project.",
        completion: .directory
    )
    var path: String?

    // MARK: - Init
    
    public init() {}
    
    // MARK: - AsyncParsableCommand
    
    public func run() async throws {
        try await CloudCleanService().clean(
            path: path
        )
    }
}
