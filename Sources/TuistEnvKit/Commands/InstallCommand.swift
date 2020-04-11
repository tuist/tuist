import Foundation
import ArgumentParser

/// Command that installs new versions of Tuist in the system.
struct InstallCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "install",
                             abstract: "Installs a version of tuist")
    }

    @Argument(
        help: "The version of tuist to be installed"
    )
    var version: String
    
    @Option(
        name: .shortAndLong,
        default: false,
        help: "Re-installs the version compiling it from the source"
    )
    var force: Bool

    func run() throws {
        try InstallService().run(version: version,
                                 force: force)
    }
}
