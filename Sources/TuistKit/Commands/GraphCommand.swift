import ArgumentParser
import Basic
import Foundation
import TuistGenerator
import TuistLoader
import TuistSupport

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
struct GraphCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "graph",
                             abstract: "Generates a dot graph from the workspace or project in the current directory")
    }

    func run() throws {
        try GraphService().run()
    }
}
