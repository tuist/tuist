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
    
    func run() throws {
        try PluginsArchiveService().run()
    }
}
