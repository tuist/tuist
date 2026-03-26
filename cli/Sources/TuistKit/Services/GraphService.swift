import Command
import DOT
import FileSystem
import Foundation
import GraphViz
import Path
import ProjectAutomation
import Tools
import TuistAlert
import TuistConfigLoader
import TuistCore
import TuistEnvironment
import TuistGenerator
import TuistLoader
import TuistLogging
import TuistPlugin
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

struct GraphService {
    private let graphVizMapper: GraphToGraphVizMapping
    private let manifestGraphLoader: ManifestGraphLoading
    private let fileSystem: FileSystem
    private let manifestLoader: ManifestLoading
    private let xcodeGraphMapper: XcodeGraphMapping
    private let configLoader: ConfigLoading
    private let commandRunner: CommandRunning

    init() {
        let manifestLoader = ManifestLoader.current
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let graphVizMapper = GraphToGraphVizMapper()
        let configLoader = ConfigLoader()
        self.init(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader,
            configLoader: configLoader
        )
    }

    init(
        graphVizGenerator: GraphToGraphVizMapping,
        manifestGraphLoader: ManifestGraphLoading,
        manifestLoader: ManifestLoading,
        xcodeGraphMapper: XcodeGraphMapping = XcodeGraphMapper(),
        fileSystem: FileSystem = FileSystem(),
        configLoader: ConfigLoading,
        commandRunner: CommandRunning = CommandRunner()
    ) {
        graphVizMapper = graphVizGenerator
        self.manifestGraphLoader = manifestGraphLoader
        self.manifestLoader = manifestLoader
        self.commandRunner = commandRunner
        self.xcodeGraphMapper = xcodeGraphMapper
        self.fileSystem = fileSystem
        self.configLoader = configLoader
    }

    func run(
        format: GraphFormat,
        layoutAlgorithm: GraphViz.LayoutAlgorithm,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        open: Bool,
        platformToFilter: Platform?,
        targetsToFilter: [String],
        path: AbsolutePath,
        outputPath: AbsolutePath
    ) async throws {
        let config = try await configLoader.loadConfig(path: path)
        let graph: XcodeGraph.Graph
        if try await manifestLoader.hasRootManifest(at: path) {
            (graph, _, _, _) = try await manifestGraphLoader.load(
                path: path,
                disableSandbox: config.project.disableSandbox
            )
        } else {
            graph = try await xcodeGraphMapper.map(at: path)
        }

        let fileExtension = switch format {
        case .legacyJSON:
            "json"
        default:
            format.rawValue
        }
        let filePath = outputPath.appending(component: "graph.\(fileExtension)")
        if try await fileSystem.exists(filePath) {
            Logger.current.notice("Deleting existing graph at \(filePath.pathString)")
            try await fileSystem.remove(filePath)
        }

        let filteredTargetsAndDependencies = graph.filter(
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            platformToFilter: platformToFilter,
            targetsToFilter: targetsToFilter
        )

        switch format {
        case .dot, .png, .svg:
            let graphVizGraph = graphVizMapper.map(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            try await export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm, open: open)
        case .json:
            try await export(graph: graph, at: filePath)
        case .legacyJSON:
            let outputGraph = ProjectAutomation.Graph.from(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            try await outputGraph.export(to: filePath)
        }

        AlertController.current.success(.alert("Graph exported to \(filePath.pathString)"))
    }

    private func export(
        graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        withFormat format: GraphFormat,
        layoutAlgorithm: LayoutAlgorithm,
        open: Bool = true
    ) async throws {
        switch format {
        case .dot:
            try await exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try await exportImageRepresentation(
                from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm, format: .png, open: open
            )
        case .svg:
            try await exportImageRepresentation(
                from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm, format: .svg, open: open
            )
        case .json:
            throw GraphServiceError.jsonNotValidForVisualExport
        case .legacyJSON:
            throw GraphServiceError.jsonNotValidForVisualExport
        }
    }

    private func export(
        graph: XcodeGraph.Graph,
        at path: AbsolutePath
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(graph)
        let jsonString = String(data: jsonData, encoding: .utf8)
        guard let jsonString else {
            throw GraphServiceError.encodingError(GraphFormat.json.rawValue)
        }

        try await fileSystem.writeText(jsonString, at: path)
    }

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) async throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try await fileSystem.writeText(dotFile, at: filePath)
    }

    private func exportImageRepresentation(
        from graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        layoutAlgorithm: LayoutAlgorithm,
        format: GraphViz.Format,
        open: Bool
    ) async throws {
        if await !isGraphVizInstalled() {
            try await installGraphViz()
        }

        let data = try Renderer(layout: layoutAlgorithm).render(graph: graph, to: format)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        if open {
            try await commandRunner.run(arguments: ["open", filePath.pathString]).awaitCompletion()
        }
    }

    private func isGraphVizInstalled() async -> Bool {
        do {
            _ = try await commandRunner.run(arguments: ["/usr/bin/env", "which", "dot"]).concatenatedString()
            return true
        } catch {
            return false
        }
    }

    private func installGraphViz() async throws {
        Logger.current.notice("Installing GraphViz...")
        try await commandRunner.run(arguments: ["brew", "install", "graphviz"]).pipedStream().awaitCompletion()
    }
}
