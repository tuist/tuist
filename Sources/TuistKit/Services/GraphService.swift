import DOT
import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport

final class GraphService {
    private let graphVizMapper: GraphToGraphVizMapping
    private let manifestGraphLoader: ManifestGraphLoading
    
    private enum GraphServiceError: Error {
        case withMessage(String)
    }

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(manifestLoader: manifestLoader)
        let graphVizMapper = GraphToGraphVizMapper()
        self.init(
            graphVizGenerator: graphVizMapper,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    init(
        graphVizGenerator: GraphToGraphVizMapping,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        graphVizMapper = graphVizGenerator
        self.manifestGraphLoader = manifestGraphLoader
    }

    func run(format: GraphFormat,
             layoutAlgorithm: GraphViz.LayoutAlgorithm,
             skipTestTargets: Bool,
             skipExternalDependencies: Bool,
             targetsToFilter: [String],
             path: AbsolutePath,
             outputPath: AbsolutePath) throws
    {
        let graph = try manifestGraphLoader.loadGraph(at: path)

        let filePath = outputPath.appending(component: "graph.\(format.rawValue)")
        if FileHandler.shared.exists(filePath) {
            logger.notice("Deleting existing graph at \(filePath.pathString)")
            try FileHandler.shared.delete(filePath)
        }
        
        switch format {
        case .dot, .png:
            let graphVizGraph = graphVizMapper.map(
                graph: graph,
                skipTestTargets: skipTestTargets,
                skipExternalDependencies: skipExternalDependencies,
                targetsToFilter: targetsToFilter
            )
            
            try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm)
        case .json:
            let jsonData = try JSONEncoder().encode(graph)
            let jsonString = String(data: jsonData, encoding: .utf8)
            guard let jsonString = jsonString else {
                throw GraphServiceError.withMessage("failed to encode graph to JSON")
            }
            
            try export(jsonContent: jsonString, at: filePath)
        }
        
        logger.notice("Graph exported to \(filePath.pathString).", metadata: .success)
    }

    private func export(graph: GraphViz.Graph,
                        at filePath: AbsolutePath,
                        withFormat format: GraphFormat,
                        layoutAlgorithm: LayoutAlgorithm) throws
    {
        switch format {
        case .dot:
            try exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try exportPNGRepresentation(from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm)
        default:
            throw GraphServiceError.withMessage("\(format.rawValue) is not a visual graph format to export")
        }
    }
    
    private func export(jsonContent: String, at filePath: AbsolutePath) throws {
        try FileHandler.shared.write(jsonContent, path: filePath, atomically: true)
    }

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    private func exportPNGRepresentation(from graphVizGraph: GraphViz.Graph,
                                         at filePath: AbsolutePath,
                                         layoutAlgorithm: LayoutAlgorithm) throws
    {
        if try !isGraphVizInstalled() {
            try installGraphViz()
        }
        let data = try graphVizGraph.render(using: layoutAlgorithm, to: .png)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        try System.shared.async(["open", filePath.pathString])
    }

    private func isGraphVizInstalled() throws -> Bool {
        try System.shared.capture(["brew", "list", "--formula"]).contains("graphviz")
    }

    private func installGraphViz() throws {
        logger.notice("Installing GraphViz...")
        var env = System.shared.env
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}
