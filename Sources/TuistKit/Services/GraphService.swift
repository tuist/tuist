import DOT
import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistLoader
import TuistSupport

final class GraphService {
    /// Dot graph generator.
    private let graphVizGenerator: GraphVizGenerating

    /// Manifest loader.
    private let manifestLoader: ManifestLoading

    init(graphVizGenerator: GraphVizGenerating = GraphVizGenerator(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                                     manifestLinter: ManifestLinter())),
    manifestLoader: ManifestLoading = ManifestLoader()) {
        self.graphVizGenerator = graphVizGenerator
        self.manifestLoader = manifestLoader
    }

    func run(format: GraphFormat,
             skipTestTargets: Bool,
             skipExternalDependencies: Bool,
             path: String?) throws {
        let graphVizGraph = try graphVizGenerator.generate(at: FileHandler.shared.currentPath,
                                                           manifestLoader: manifestLoader,
                                                           skipTestTargets: skipTestTargets,
                                                           skipExternalDependencies: skipExternalDependencies)
        let basePath = path != nil ? path! : FileHandler.shared.currentPath.pathString
        let filePath = AbsolutePath(basePath).appending(component: "graph.\(format.rawValue)")
        if FileHandler.shared.exists(filePath) {
            logger.notice("Deleting existing graph at \(filePath.pathString)")
            try FileHandler.shared.delete(filePath)
        }
        try export(graph: graphVizGraph, at: filePath, withFormat: format)
        logger.notice("Graph exported to \(filePath.pathString).", metadata: .success)
    }

    private func export(graph: GraphViz.Graph, at filePath: AbsolutePath, withFormat format: GraphFormat) throws {
        switch format {
        case .dot:
            try exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try exportPNGRepresentation(from: graph, at: filePath)
        }
    }

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    private func exportPNGRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let data = try graphVizGraph.render(using: .circo, to: .png)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        try System.shared.async(["open", filePath.pathString])
    }
}
