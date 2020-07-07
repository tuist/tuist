import ArgumentParser
import Foundation
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
struct GraphCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "graph",
                             abstract: "Generates a dot graph from the workspace or project in the current directory")
    }

    @Flag(
        help: "Skip Test targets during graph rendering."
    )
    var skipTestTargets: Bool

    @Flag(
        help: "Skip external dependencies."
    )
    var skipExternalParty: Bool

    func run() throws {
        try GraphService().run(skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalParty)
    }
}
