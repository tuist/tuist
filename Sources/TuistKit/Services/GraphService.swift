import DOT
import FileSystem
import Foundation
import GraphViz
import Path
import ProjectAutomation
import ServiceContextModule
import Tools
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

final class GraphService {
    private let graphVizMapper: GraphToGraphVizMapping
    private let manifestGraphLoader: ManifestGraphLoading
    private let fileSystem: FileSystem
    private let manifestLoader: ManifestLoading
    private let xcodeGraphMapper: XcodeGraphMapping

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let graphVizMapper = GraphToGraphVizMapper()
        self.init(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader,
            manifestLoader: manifestLoader
        )
    }

    init(
        graphVizGenerator: GraphToGraphVizMapping,
        manifestGraphLoader: ManifestGraphLoading,
        manifestLoader: ManifestLoading,
        xcodeGraphMapper: XcodeGraphMapping = XcodeGraphMapper(),
        fileSystem: FileSystem = FileSystem()
    ) {
        graphVizMapper = graphVizGenerator
        self.manifestGraphLoader = manifestGraphLoader
        self.manifestLoader = manifestLoader
        self.xcodeGraphMapper = xcodeGraphMapper
        self.fileSystem = fileSystem
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
        let graph: XcodeGraph.Graph
        if try await manifestLoader.hasRootManifest(at: path) {
            (graph, _, _, _) = try await manifestGraphLoader.load(path: path)
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
            ServiceContext.current?.logger?.notice("Deleting existing graph at \(filePath.pathString)")
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
            try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm, open: open)
        case .json:
            try await export(graph: graph, at: filePath)
        case .legacyJSON:
            let outputGraph = ProjectAutomation.Graph.from(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            try outputGraph.export(to: filePath)
        }

        ServiceContext.current?.alerts?.append(.success(.alert("Graph exported to \(filePath.pathString)")))
    }

    private func export(
        graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        withFormat format: GraphFormat,
        layoutAlgorithm: LayoutAlgorithm,
        open: Bool = true
    ) throws {
        switch format {
        case .dot:
            try exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try exportImageRepresentation(from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm, format: .png, open: open)
        case .svg:
            try exportImageRepresentation(from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm, format: .svg, open: open)
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

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    private func exportImageRepresentation(
        from graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        layoutAlgorithm: LayoutAlgorithm,
        format: GraphViz.Format,
        open: Bool
    ) throws {
        if !isGraphVizInstalled() {
            try installGraphViz()
        }

        let data = try Renderer(layout: layoutAlgorithm).render(graph: graph, to: format)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        if open {
            try System.shared.async(["open", filePath.pathString])
        }
    }

    private func isGraphVizInstalled() -> Bool {
        System.shared.commandExists("dot")
    }

    private func installGraphViz() throws {
        ServiceContext.current?.logger?.notice("Installing GraphViz...")
        var env = System.shared.env
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}
