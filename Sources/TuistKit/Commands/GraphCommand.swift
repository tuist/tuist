import AnyCodable
import ArgumentParser
import Foundation
import GraphViz
import Path
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
public struct GraphCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}

    public static var analyticsDelegate: TrackableParametersDelegate?
    public var runId = UUID().uuidString

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "graph",
            abstract: "Generates a graph from the workspace or project in the current directory"
        )
    }

    @Flag(
        name: [.customShort("t"), .long],
        help: "Skip Test targets during graph rendering.",
        envKey: .graphSkipTestTargets
    )
    var skipTestTargets: Bool = false

    @Flag(
        name: [.customShort("d"), .long],
        help: "Skip external dependencies.",
        envKey: .graphSkipExternalDependencies
    )
    var skipExternalDependencies: Bool = false

    @Option(
        name: [.customShort("l"), .long],
        help: "A platform to filter. Only targets for this platform will be showed in the graph. Available platforms: ios, macos, tvos, watchos",
        envKey: .graphPlatform
    )
    var platform: Platform?

    @Option(
        name: [.customShort("f"), .long],
        help: "Available formats: dot, json, png, svg",
        envKey: .graphFormat
    )
    var format: GraphFormat = .png

    @Flag(
        name: .long,
        help: "Don't open the file after generating it.",
        envKey: .graphOpen
    )
    var open: Bool = true

    @Option(
        name: [.customShort("a"), .customLong("algorithm")],
        help: "Available formats: dot, neato, twopi, circo, fdp, sfdp, patchwork",
        envKey: .graphLayoutAlgorithm
    )
    var layoutAlgorithm: GraphViz.LayoutAlgorithm = .dot

    @Argument(
        help: "A list of targets to filter. Those and their dependent targets will be showed in the graph.",
        envKey: .graphTargets
    )
    var targets: [String] = []

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project whose targets will be cached.",
        completion: .directory,
        envKey: .graphPath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The path where the graph will be generated.",
        envKey: .graphOutputPath
    )
    var outputPath: String?

    public func run() async throws {
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
            open: open,
            platformToFilter: platform,
            targetsToFilter: targets,
            path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath,
            outputPath: outputPath
                .map { try AbsolutePath(validating: $0, relativeTo: FileHandler.shared.currentPath) } ?? FileHandler.shared
                .currentPath
        )
    }
}

enum GraphFormat: String, ExpressibleByArgument, CaseIterable {
    case dot, json, png, svg
}

extension GraphViz.LayoutAlgorithm: ExpressibleByArgument {
    public static var allValueStrings: [String] {
        [
            LayoutAlgorithm.dot.rawValue,
            LayoutAlgorithm.neato.rawValue,
            LayoutAlgorithm.twopi.rawValue,
            LayoutAlgorithm.circo.rawValue,
            LayoutAlgorithm.fdp.rawValue,
            LayoutAlgorithm.sfdp.rawValue,
            LayoutAlgorithm.patchwork.rawValue,
        ]
    }
}
