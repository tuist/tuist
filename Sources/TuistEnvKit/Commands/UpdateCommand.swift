import Foundation
import ArgumentParser
import TuistSupport

/// Command that updates the version of Tuist in the environment.
struct UpdateCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "update",
                             abstract: "Installs the latest version if it's not already installed")
    }

    /// Force argument (-f). When passed, it re-installs the latest version compiling it from the source.
    @Option(
        name: .shortAndLong,
        default: false,
        help: "Re-installs the latest version compiling it from the source"
    )
    var force: Bool

    func run() throws {
        try UpdateService().run(force: force)
    }
}
