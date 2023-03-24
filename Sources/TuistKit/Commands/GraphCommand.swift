import AnyCodable
import ArgumentParser
import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistGraph
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
        name: [.customShort("l"), .long],
        help: "A platform to filter. Only targets for this platform will be showed in the graph. Available platforms: ios, macos, tvos, watchos"
    )
    var platform: Platform?

    @Option(
        name: [.customShort("f"), .long],
        help: "Available formats: dot, json, png, svg"
    )
    var format: GraphFormat = .png

    @Flag(
        name: .shortAndLong,
        help: "Don't open the file after generating it."
    )
    var noOpen: Bool = false

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

    func run() async throws {
        GraphCommand.analyticsDelegate?.addParameters(
            [
                "format": AnyCodable(format.rawValue),
                "algorithm": AnyCodable(layoutAlgorithm.rawValue),
                "skip_external_dependencies": AnyCodable(skipExternalDependencies),
                "skip_test_targets": AnyCodable(skipExternalDependencies),
            ]
        )
        try await GraphService().run(
            format: format,
            layoutAlgorithm: layoutAlgorithm,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            open: !noOpen,
            platformToFilter: platform,
            targetsToFilter: targets,
            path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath,
            outputPath: outputPath
                .map { try AbsolutePath(validating: $0, relativeTo: FileHandler.shared.currentPath) } ?? FileHandler.shared
                .currentPath
        )
    }
}

enum GraphFormat: String, ExpressibleByArgument {
    case dot, json, png, svg
}

extension GraphViz.LayoutAlgorithm: ExpressibleByArgument {}

extension TuistGraph.Platform: ExpressibleByArgument {}
