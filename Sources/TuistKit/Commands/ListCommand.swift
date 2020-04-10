import Foundation
import ArgumentParser

struct ListCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "list",
             abstract: "Lists available scaffold templates",
             subcommands: [])
    }
    
    @Option(
        name: .shortAndLong,
        help: "The path where you want to list templates from"
    )
    var path: String?
    
    func run() throws {
        try ListService().run(path: path)
    }
}
