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
    /// Dot graph generator.
    private let graphVizGenerator: GraphVizGenerating

    /// Manifest loader.
    private let manifestLoader: ManifestLoading

    /// The plugin service
    private let pluginsService: PluginServicing

    /// The graph loader
    private let graphLoader: GraphLoading

    init() {
        let manifestLinter = ManifestLinter()
        manifestLoader = ManifestLoader()

        graphVizGenerator = GraphVizGenerator(
            modelLoader: GeneratorModelLoader(
                manifestLoader: manifestLoader,
                manifestLinter: manifestLinter
            )
        )

        let modelLoader = GeneratorModelLoader(
            manifestLoader: manifestLoader,
            manifestLinter: manifestLinter
        )

        graphLoader = GraphLoader(modelLoader: modelLoader)
        pluginsService = PluginService(manifestLoader: manifestLoader)
    }

    init(
        graphVizGenerator: GraphVizGenerating,
        manifestLoader: ManifestLoading,
        pluginsService: PluginServicing,
        graphLoader: GraphLoading
    ) {
        self.graphVizGenerator = graphVizGenerator
        self.manifestLoader = manifestLoader
        self.pluginsService = pluginsService
        self.graphLoader = graphLoader
    }

    func run(format: GraphFormat,
             layoutAlgorithm: GraphViz.LayoutAlgorithm,
             skipTestTargets: Bool,
             skipExternalDependencies: Bool,
             targetsToFilter: [String],
             path: AbsolutePath,
             outputPath: AbsolutePath) throws
    {
        // Load config
        let config = try graphLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)

        // Generate the graph
        let graphVizGraph = try graphVizGenerator.generate(at: path,
                                                           manifestLoader: manifestLoader,
                                                           skipTestTargets: skipTestTargets,
                                                           skipExternalDependencies: skipExternalDependencies,
                                                           targetsToFilter: targetsToFilter)
        let filePath = outputPath.appending(component: "graph.\(format.rawValue)")
        if FileHandler.shared.exists(filePath) {
            logger.notice("Deleting existing graph at \(filePath.pathString)")
            try FileHandler.shared.delete(filePath)
        }
        try export(graph: graphVizGraph, at: filePath, withFormat: format, layoutAlgorithm: layoutAlgorithm)
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
        }
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
