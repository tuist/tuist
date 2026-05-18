import ArgumentParser
import Foundation
import GraphViz
import Path
import TuistEnvironment
import TuistGenerator
import TuistLoader
import TuistSupport
import XcodeGraph

/// Command that generates and exports a dot graph from the workspace or project in the current directory.
public struct GraphCommand: AsyncParsableCommand {
    public init() {}

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

    @Flag(
        name: [.customShort("m"), .long],
        help: "Skip Swift Macro support targets (SwiftSyntax, SwiftCompilerPlugin, etc.). Macro plugin targets themselves are still shown.",
        envKey: .graphSkipMacroSupportTargets
    )
    var skipMacroSupportTargets: Bool = false

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
        let cwd = try await Environment.current.currentWorkingDirectory()
        try await GraphService().run(
            format: format,
            layoutAlgorithm: layoutAlgorithm,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            skipMacroSupportTargets: skipMacroSupportTargets,
            open: open,
            platformToFilter: platform,
            targetsToFilter: targets,
            path: path.map { try AbsolutePath(validating: $0) } ?? cwd,
            outputPath: outputPath
                .map { try AbsolutePath(validating: $0, relativeTo: cwd) } ?? cwd
        )
    }
}

enum GraphFormat: String, ExpressibleByArgument, CaseIterable {
    case dot, json, legacyJSON, png, svg
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
