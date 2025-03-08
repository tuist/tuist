import ArgumentParser
import Foundation
import GraphViz
import Path
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
public struct GraphCommand: AsyncParsableCommand {

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

    public init() {}

    public func run() async throws {
        // If output path is present
        var absoluteOutputPath: AbsolutePath?
        if let outputPath {
            absoluteOutputPath = try AbsolutePath(validating: outputPath, relativeTo: FileHandler.shared.currentPath)
        }

        try await GraphService().run(
            format: format,
            layoutAlgorithm: layoutAlgorithm,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            open: open,
            platformToFilter: platform,
            targetsToFilter: targets,
            path: path.map { try AbsolutePath(validating: $0) } ?? FileHandler.shared.currentPath,
            outputPath: absoluteOutputPath
        )
    }
}

enum GraphFormat: String, ExpressibleByArgument, CaseIterable {
    case dot, json, legacyJSON, png, svg
}

extension GraphFormat {
    /// Flag to indicate if an output to stdout is allowed.
    var allowsStdOut: Bool {
        switch self {
        case .json, .svg, .dot:
            return true
        default:
            return false
        }
    }
}

extension GraphViz.LayoutAlgorithm: ArgumentParser.ExpressibleByArgument {
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
