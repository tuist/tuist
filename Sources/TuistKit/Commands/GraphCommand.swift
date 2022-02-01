import ArgumentParser
import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
struct GraphCommand: AsyncParsableCommand, HasTrackableParameters {
    static var analyticsDelegate: TrackableParametersDelegate?

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "graph",
            abstract: "Generates a graph from the workspace or project in the current directory"
        )
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
        help: "Available formats: dot, png, json"
    )
    var format: GraphFormat = .png

    @Option(
        name: [.customShort("a"), .customLong("algorithm")],
        help: "Available formats: dot, neato, twopi, circo, fdp, sfddp, patchwork"
    )
    var layoutAlgorithm: GraphViz.LayoutAlgorithm = .dot

    @Argument(help: "A list of targets to filter. Those and their dependent targets will be showed in the graph.")
    var targets: [String] = []

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The path where the graph will be generated."
    )
    var outputPath: String?

    func runAsync() async throws {
        GraphCommand.analyticsDelegate?.willRun(withParameters: [
            "format": format.rawValue,
            "algorithm": layoutAlgorithm.rawValue,
            "skip_external_dependencies": String(skipExternalDependencies),
            "skip_test_targets": String(skipExternalDependencies),
        ])
        try await GraphService().run(
            format: format,
            layoutAlgorithm: layoutAlgorithm,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            targetsToFilter: targets,
            path: path.map { AbsolutePath($0) } ?? FileHandler.shared.currentPath,
            outputPath: outputPath.map { AbsolutePath($0, relativeTo: FileHandler.shared.currentPath) } ?? FileHandler.shared
                .currentPath
        )
    }
}

enum GraphFormat: String, ExpressibleByArgument {
    case dot, png, json
}

extension GraphViz.LayoutAlgorithm: ExpressibleByArgument {}
