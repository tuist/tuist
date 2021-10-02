import ArgumentParser
import Foundation
import TSCBasic

struct PluginsArchiveCommannd: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "archive",
            abstract: "Archives plugins and saves the artifacts into `build` directory."
        )
    }
    
    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the definition of the plugin.",
        completion: .directory
    )
    var path: String?
    
    func run() throws {
        try PluginsArchiveService().run(
            path: path
        )
    }
}
