import Basic
import Foundation
import ArgumentParser

/// Command that builds a target from the project in the current directory.
struct BuildCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "build",
                             abstract: "Builds a project target")
    }
    
    func run() throws {
        try BuildService().run()
    }
}
