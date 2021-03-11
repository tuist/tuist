import ArgumentParser
import Foundation
import TuistSupport

/// Command that updates the version of Tuist in the environment.
struct UpdateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "update",
            abstract: "Installs the latest version if it's not already installed"
        )
    }

    func run() throws {
        try UpdateService().run()
    }
}
