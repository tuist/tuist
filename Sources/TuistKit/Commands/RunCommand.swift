import ArgumentParser
import Foundation
import TSCBasic

/// Command that builds and runs a target from the project in the current directory.
struct RunCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "run",
                             abstract: "Builds and runs a project")
    }

    @Argument(
        help: "The scheme to be run."
    )
    var scheme: String

    func run() throws {
        try RunService().run(schemeName: scheme)
    }
}
