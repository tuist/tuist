import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistSupport

public protocol GraphVizGenerating {
    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameters:
    ///   - path: The path to the project manifest.
    ///   - skipTestTargets: Whether to skip test targets or not.
    ///   - skipExternalDependencies: Whether to skip external dependencies.
    ///   - plugins: Any loaded plugins used to generate the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    func generateProject(
        at path: AbsolutePath,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        plugins: Plugins
    ) throws -> GraphViz.Graph

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameters:
    ///   - path: The path to the project manifest.
    ///   - skipTestTargets: Whether to skip test targets or not.
    ///   - skipExternalDependencies: Whether to skip external dependencies.
    ///   - plugins: Any loaded plugins used to generate the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    func generateWorkspace(
        at path: AbsolutePath,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        plugins: Plugins
    ) throws -> GraphViz.Graph
}

public final class GraphVizGenerator: GraphVizGenerating {
    /// Graph loader.
    private let graphLoader: GraphLoading

    /// Mapper to map graphs into a GraphViz.Graph.
    private let graphToGraphVizMapper: GraphToGraphVizMapping

    /// Initializes the dot graph generator by taking its dependencies.
    ///
    /// - Parameters:
    ///   - modelLoader: Instance to load the models.
    public convenience init(modelLoader: GeneratorModelLoading) {
        let graphLoader = GraphLoader(modelLoader: modelLoader)
        self.init(graphLoader: graphLoader, graphToGraphVizMapper: GraphToGraphVizMapper())
    }

    /// Initializes the generator with an instance to load the graph.
    ///
    /// - Parameters:
    ///   - graphLoader: Graph loader instance.
    ///   - graphToDotGraphMapper: Mapper to map the graph into a dot graph.
    init(
        graphLoader: GraphLoading,
        graphToGraphVizMapper: GraphToGraphVizMapping
    ) {
        self.graphLoader = graphLoader
        self.graphToGraphVizMapper = graphToGraphVizMapper
    }

    /// Generates the GraphViz.Graph from the project in the current directory and returns it.
    ///
    /// - Parameters:
    ///   - path: The path to the project manifest.
    ///   - skipTestTargets: Whether to skip test targets or not.
    ///   - skipExternalDependencies: Whether to skip external dependencies.
    ///   - plugins: Any loaded plugins used to generate the project.
    /// - Returns: GraphViz graph representation.
    /// - Throws: An error if the project can't be loaded.
    public func generateProject(
        at path: AbsolutePath,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        plugins: Plugins
    ) throws -> GraphViz.Graph {
        let (graph, _) = try graphLoader.loadProject(path: path, plugins: plugins)
        return graphToGraphVizMapper.map(graph: graph, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
    }

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameters:
    ///   - path: The path to the project manifest.
    ///   - skipTestTargets: Whether to skip test targets or not.
    ///   - skipExternalDependencies: Whether to skip external dependencies.
    ///   - plugins: Any loaded plugins used to generate the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    public func generateWorkspace(
        at path: AbsolutePath,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        plugins: Plugins
    ) throws -> GraphViz.Graph {
        let graph = try graphLoader.loadWorkspace(path: path, plugins: plugins)
        return graphToGraphVizMapper.map(graph: graph, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
    }
}
