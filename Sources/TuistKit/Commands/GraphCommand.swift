import ArgumentParser
import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
struct GraphCommand: ParsableCommand, HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate?

    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "graph",
                             abstract: "Generates a graph from the workspace or project in the current directory")
    }

    @Flag(
        name: [.customShort("t"), .long],
        help: "Skip Test targets during graph rendering."
    )
    var skipTestTargets: Bool = false

    @Flag(
        name: [.customShort("d"), .long],
        help: "Skip external dependencies."
    )
    var skipExternalDependencies: Bool = false

    @Option(
        name: [.customShort("f"), .long],
        help: "Available formats: dot, png"
    )
    var format: GraphFormat = .png

    @Option(
        name: [.customShort("a"), .customLong("algorithm")],
        help: "Available formats: dot, neato, twopi, circo, fdp, sfddp, patchwork"
    )
    var layoutAlgorithm: GraphViz.LayoutAlgorithm = .dot

    @Option(
        name: .shortAndLong,
        help: "The path where the graph will be generated."
    )
    var path: String?

    func run() throws {
        GraphCommand.analyticsDelegate?.willRun(withParameters: ["format": format.rawValue,
                                                                 "algorithm": layoutAlgorithm.rawValue,
                                                                 "skip_external_dependencies": String(skipExternalDependencies),
                                                                 "skip_test_targets": String(skipExternalDependencies)])
        try GraphService().run(format: format,
                               layoutAlgorithm: layoutAlgorithm,
                               skipTestTargets: skipTestTargets,
                               skipExternalDependencies: skipExternalDependencies,
                               path: path)
    }
}

enum GraphFormat: String, ExpressibleByArgument {
    case dot, png
}

extension GraphViz.LayoutAlgorithm: ExpressibleByArgument {}
