import ArgumentParser
import Foundation

// MARK: - DocCommand

struct DocCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "doc",
                             abstract: "Generates documentation for a specifc target.")
    }
    
    // MARK: - Attributes
    
    @Option(
        name: .shortAndLong,
        help: "The path to target sources folder",
        completion: .directory
    )
    var path: String?
    
    // MARK: - Run

    func run() throws {
        
    }
}
