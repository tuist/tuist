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
             layoutAlgorithm: GraphViz.LayoutAlgorithm,
             skipTestTargets: Bool,
             skipExternalDependencies: Bool,
             path: String?) throws {
        let graphVizGraph = try graphVizGenerator.generate(at: FileHandler.shared.currentPath,
                                                           manifestLoader: manifestLoader,
                                                           skipTestTargets: skipTestTargets,
                                                           skipExternalDependencies: skipExternalDependencies)
        let filePath = makeAbsolutePath(from: path).appending(component: "graph.\(format.rawValue)")
        if FileHandler.shared.exists(filePath) {
            logger.notice("Deleting existing graph at \(filePath.pathString)")
            try FileHandler.shared.delete(filePath)
        }
        try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm)
        logger.notice("Graph exported to \(filePath.pathString).", metadata: .success)
    }

    private func makeAbsolutePath(from path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func export(graph: GraphViz.Graph,
                        at filePath: AbsolutePath,
                        withFormat format: GraphFormat,
                        layoutAlgorithm: LayoutAlgorithm) throws {
        switch format {
        case .dot:
            try exportDOTRepresentation(from: graph, at: filePath)
        case .png:
            try exportPNGRepresentation(from: graph, at: filePath, layoutAlgorithm: layoutAlgorithm)
        }
    }

    private func exportDOTRepresentation(from graphVizGraph: GraphViz.Graph, at filePath: AbsolutePath) throws {
        let dotFile = DOTEncoder().encode(graphVizGraph)
        try FileHandler.shared.write(dotFile, path: filePath, atomically: true)
    }

    private func exportPNGRepresentation(from graphVizGraph: GraphViz.Graph,
                                         at filePath: AbsolutePath,
                                         layoutAlgorithm: LayoutAlgorithm) throws {
        if try !isGraphVizInstalled() {
            try installGraphViz()
        }
        let data = try graphVizGraph.render(using: layoutAlgorithm, to: .png)
        FileManager.default.createFile(atPath: filePath.pathString, contents: data, attributes: nil)
        try System.shared.async(["open", filePath.pathString])
    }

    private func isGraphVizInstalled() throws -> Bool {
        try System.shared.capture(["brew", "list"]).contains("graphviz")
    }

    private func installGraphViz() throws {
        logger.notice("Installing GraphViz...")
        var env = System.shared.env
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        try System.shared.runAndPrint(["brew", "install", "graphviz"], verbose: false, environment: env)
    }
}
