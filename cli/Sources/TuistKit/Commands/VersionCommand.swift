import ArgumentParser
import Foundation
import Path

struct VersionCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "version",
            abstract: "Outputs the current version of tuist"
        )
    }

    func run() throws {
        try VersionService().run()
    }
}
