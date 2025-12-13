import DOT
import FileSystem
import Foundation
import GraphViz
import Path
import ProjectAutomation
import Tools
import ToonFormat
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

final class GraphCommandService {
    private let graphVizMapper: GraphToGraphVizMapping
    private let manifestGraphLoader: ManifestGraphLoading
    private let fileSystem: FileSystem
    private let manifestLoader: ManifestLoading
    private let xcodeGraphMapper: XcodeGraphMapping
    private let configLoader: ConfigLoading

    convenience init() {
        let manifestLoader = ManifestLoader.current
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        let graphVizMapper = GraphToGraphVizMapper()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
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
        configLoader: ConfigLoading
    ) {
        graphVizMapper = graphVizGenerator
        self.manifestGraphLoader = manifestGraphLoader
        self.manifestLoader = manifestLoader
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
        sourceTargets: [String],
        sinkTargets: [String],
        directOnly: Bool,
        labelFilter: Set<GraphDependencyLabel>,
        outputFields _: Set<GraphOutputField>?,
        path: AbsolutePath,
        outputPath: AbsolutePath,
        stdout: Bool
    ) async throws {
        if stdout {
            switch format {
            case .png, .svg:
                throw GraphServiceError.stdoutNotSupportedForFormat(format)
            case .dot, .json, .toon, .legacyJSON:
                break
            }
        }
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

        let filteredTargetsAndDependencies = graph.filter(
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            platformToFilter: platformToFilter,
            targetsToFilter: targetsToFilter,
            sourceTargets: sourceTargets,
            sinkTargets: sinkTargets,
            directOnly: directOnly,
            labelFilter: labelFilter
        )

        if stdout {
            let output = try await generateOutput(
                format: format,
                graph: graph,
                filteredTargetsAndDependencies: filteredTargetsAndDependencies
            )
            print(output)
            return
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

        switch format {
        case .dot, .png, .svg:
            let graphVizGraph = graphVizMapper.map(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm, open: open)
        case .json:
            try await jsonExport(graph: graph, at: filePath)
        case .toon:
            try await toonExport(graph: graph, at: filePath)
        case .legacyJSON:
            let outputGraph = ProjectAutomation.Graph.from(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            try outputGraph.export(to: filePath)
        }

        AlertController.current.success(.alert("Graph exported to \(filePath.pathString)"))
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
        case .toon:
            throw GraphServiceError.toonNotValidForVisualExport
        case .legacyJSON:
            throw GraphServiceError.jsonNotValidForVisualExport
        }
    }

    private func jsonExport(
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

    private func toonExport(
        graph: XcodeGraph.Graph,
        at path: AbsolutePath
    ) async throws {
        let encoder = TOONEncoder()
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

    private func generateOutput(
        format: GraphFormat,
        graph: XcodeGraph.Graph,
        filteredTargetsAndDependencies: [GraphTarget: Set<GraphDependency>]
    ) async throws -> String {
        switch format {
        case .dot:
            let graphVizGraph = graphVizMapper.map(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            return DOTEncoder().encode(graphVizGraph)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            let jsonData = try encoder.encode(graph)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw GraphServiceError.encodingError(GraphFormat.json.rawValue)
            }
            return jsonString
        case .toon:
            let encoder = TOONEncoder()
            let jsonData = try encoder.encode(graph)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw GraphServiceError.encodingError(GraphFormat.toon.rawValue)
            }
            return jsonString
        case .legacyJSON:
            let outputGraph = ProjectAutomation.Graph.from(graph: graph, targetsAndDependencies: filteredTargetsAndDependencies)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let jsonData = try encoder.encode(outputGraph)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw GraphServiceError.encodingError(GraphFormat.legacyJSON.rawValue)
            }
            return jsonString
        case .png, .svg:
            throw GraphServiceError.stdoutNotSupportedForFormat(format)
        }
    }

    private func isGraphVizInstalled() -> Bool {
        System.shared.commandExists("dot")
    }

    private func installGraphViz() throws {
        Logger.current.notice("Installing GraphViz...")
        var env = Environment.current.variables
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}
