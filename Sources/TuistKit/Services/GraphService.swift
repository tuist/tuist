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
        outputPath: AbsolutePath?
    ) async throws {
        // Sanity checks
        if outputPath == nil, !format.allowsStdOut {
            throw GraphServiceError.outputPathMissingForVisualExport(format)
        }

        // Generate Graph representation
        let graph: XcodeGraph.Graph
        if try await manifestLoader.hasRootManifest(at: path) {
            (graph, _, _, _) = try await manifestGraphLoader.load(path: path)
        } else {
            graph = try await xcodeGraphMapper.map(at: path)
        }

        // Filter targets
        let filteredTargetsAndDependencies = graph.filter(
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            platformToFilter: platformToFilter,
            targetsToFilter: targetsToFilter
        )

        // Decide export type
        if let outputPath {
            try await exportToFile(
                graph: graph,
                outputPath: outputPath,
                withFormat: format,
                layoutAlgorithm: layoutAlgorithm,
                targetsAndDependencies: filteredTargetsAndDependencies,
                open: open
            )
        } else {
            try await exportToStdout(
                graph: graph,
                withFormat: format,
                layoutAlgorithm: layoutAlgorithm,
                targetsAndDependencies: filteredTargetsAndDependencies
            )
        }
    }
}

// MARK: - Exports

// MARK: - stdout Export

extension GraphService {
    private func exportToStdout(
        graph: XcodeGraph.Graph,
        withFormat format: GraphFormat,
        layoutAlgorithm: GraphViz.LayoutAlgorithm,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) async throws {
        switch format {
        case .svg, .dot:
            let graphVizGraph = graphVizMapper.map(graph: graph, targetsAndDependencies: targetsAndDependencies)
            try exportGraphVizToStdOut(graph: graphVizGraph, withFormat: format, layoutAlgorithm: layoutAlgorithm)
        case .json:
            try exportJSONRepresentationToStdout(from: graph)
        default:
            throw GraphServiceError.formatNotValidForStdExport(format)
        }
    }

    // MARK: JSON Export

    /// Export a JSON representation of a XcodeGraph graph to stdout.
    /// - Parameters:
    ///   - graph: Graph to export.
    private func exportJSONRepresentationToStdout(
        from graph: XcodeGraph.Graph
    ) throws {
        let jsonString = try json(from: graph)
        ServiceContext.current?.ui?.message("\(jsonString)")
    }

    // MARK: GraphViz Export

    private func exportGraphVizToStdOut(
        graph: GraphViz.Graph,
        withFormat format: GraphFormat,
        layoutAlgorithm: LayoutAlgorithm
    ) throws {
        switch format {
        case .svg:
            let imageData = try imageData(from: graph, layoutAlgorithm: layoutAlgorithm, format: .svg)
            guard let string = String(data: imageData, encoding: .utf8) else {
                throw GraphServiceError.encodingError(GraphFormat.svg.rawValue)
            }
            ServiceContext.current?.logger?.notice("\(string)")
        case .dot:
            let dotString = dotData(from: graph)
            ServiceContext.current?.logger?.notice("\(dotString)")
        default:
            throw GraphServiceError.formatNotValidForStdExport(format)
        }
    }
}

// MARK: - File Export

extension GraphService {
    private func exportToFile(
        graph: XcodeGraph.Graph,
        outputPath: AbsolutePath,
        withFormat format: GraphFormat,
        layoutAlgorithm: GraphViz.LayoutAlgorithm,
        targetsAndDependencies: [GraphTarget: Set<GraphDependency>],
        open: Bool = true
    ) async throws {
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

        switch format {
        case .dot, .png, .svg:
            let graphVizGraph = graphVizMapper.map(graph: graph, targetsAndDependencies: targetsAndDependencies)
            try exportGraphViz(
                graph: graphVizGraph,
                at: filePath,
                withFormat: format,
                layoutAlgorithm: layoutAlgorithm,
                open: open
            )
        case .json:
            try await exportJSONRepresentation(from: graph, at: filePath)
        case .legacyJSON:
            let outputGraph = ProjectAutomation.Graph.from(graph: graph, targetsAndDependencies: targetsAndDependencies)
            try outputGraph.export(to: filePath)
        }

        ServiceContext.current?.alerts?.success(.alert("Graph exported to \(filePath.pathString)"))
    }

    // MARK: JSON Export

    /// Export a JSON representation of a XcodeGraph graph to a file.
    /// - Parameters:
    ///   - graph: Graph to export.
    ///   - path: File path to export to
    private func exportJSONRepresentation(
        from graph: XcodeGraph.Graph,
        at path: AbsolutePath
    ) async throws {
        let jsonString = try json(from: graph)
        try await fileSystem.writeText(jsonString, at: path)
    }

    // MARK: - GraphViz Export

    private func exportGraphViz(
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

    /// Export a `dot` representation of a GraphViz graph to a file.
    /// - Parameters:
    ///   - graphVizGraph: Graph to export.
    ///   - filePath: File path to export to.
    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = dotData(from: graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    /// Export an image from a GraphViz graph to a file.
    ///
    /// - Parameters:
    ///   - graph: Graph to export.
    ///   - filePath: Gile path to export to.
    ///   - layoutAlgorithm: LayoutAlgorithm to use.
    ///   - format: Format to export to.
    ///   - open: Flag to open file after export.
    private func exportImageRepresentation(
        from graph: GraphViz.Graph,
        at filePath: AbsolutePath,
        layoutAlgorithm: LayoutAlgorithm,
        format: GraphViz.Format,
        open: Bool
    ) throws {
        let data = try imageData(from: graph, layoutAlgorithm: layoutAlgorithm, format: format)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        if open {
            try System.shared.async(["open", filePath.pathString])
        }
    }
}

// MARK: - Helpers

extension GraphService {
    private func imageData(
        from graph: GraphViz.Graph,
        layoutAlgorithm: LayoutAlgorithm,
        format: GraphViz.Format
    ) throws -> Data {
        if !isGraphVizInstalled() {
            try installGraphViz()
        }

        return try Renderer(layout: layoutAlgorithm).render(graph: graph, to: format)
    }

    private func dotData(
        from graph: GraphViz.Graph
    ) -> String {
        return DOTEncoder().encode(graph)
    }

    private func json(from graph: XcodeGraph.Graph) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let jsonData = try encoder.encode(graph)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw GraphServiceError.encodingError(GraphFormat.json.rawValue)
        }

        return jsonString
    }
}

// MARK: - GraphViz installation

extension GraphService {
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
