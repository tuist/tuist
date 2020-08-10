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
                             abstract: "Generates a graph from the workspace or project in the current directory")
    }

    @Flag(
        help: "Skip Test targets during graph rendering."
    )
    var skipTestTargets: Bool

    @Flag(
        help: "Skip external dependencies."
    )
    var skipExternalDependencies: Bool

    @Option(
        default: .dot,
        help: "Available formats: dot, png"
    )
    var format: GraphFormat

    @Option(
        name: .shortAndLong,
        help: "The path where the graph will be generated."
    )
    var path: String?

    func run() throws {
        try GraphService().run(format: format,
                               skipTestTargets: skipTestTargets,
                               skipExternalDependencies: skipExternalDependencies,
                               path: path)
    }
}

enum GraphFormat: String, ExpressibleByArgument {
    case dot, png
}
