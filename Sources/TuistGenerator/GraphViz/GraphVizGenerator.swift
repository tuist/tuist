import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol GraphVizGenerating {
    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    func generateProject(at path: AbsolutePath,
                         skipTestTargets: Bool,
                         skipExternalDependencies: Bool,
                         targetsToFilter: [String]) throws -> GraphViz.Graph

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    func generateWorkspace(at path: AbsolutePath,
                           skipTestTargets: Bool,
                           skipExternalDependencies: Bool,
                           targetsToFilter: [String]) throws -> GraphViz.Graph
}

public final class GraphVizGenerator: GraphVizGenerating {
    /// Graph loader.
    private let graphLoader: ValueGraphLoading

    private let modelLoader: GeneratorModelLoading

    /// Mapper to map graphs into a GraphViz.Graph.
    private let graphToGraphVizMapper: GraphToGraphVizMapping

    /// Initializes the dot graph generator by taking its dependencies.
    ///
    /// - Parameters:
    ///   - modelLoader: Instance to load the models.
    public convenience init(modelLoader: GeneratorModelLoading) {
        self.init(
            graphLoader: ValueGraphLoader(),
            modelLoader: modelLoader,
            graphToGraphVizMapper: GraphToGraphVizMapper()
        )
    }

    /// Initializes the generator with an instance to load the graph.
    ///
    /// - Parameters:
    ///   - graphLoader: Graph loader instance.
    ///   - graphToDotGraphMapper: Mapper to map the graph into a dot graph.
    init(
        graphLoader: ValueGraphLoading,
        modelLoader: GeneratorModelLoading,
        graphToGraphVizMapper: GraphToGraphVizMapping
    ) {
        self.graphLoader = graphLoader
        self.modelLoader = modelLoader
        self.graphToGraphVizMapper = graphToGraphVizMapper
    }

    /// Generates the GraphViz.Graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: GraphViz graph representation.
    /// - Throws: An error if the project can't be loaded.
    public func generateProject(at path: AbsolutePath,
                                skipTestTargets: Bool,
                                skipExternalDependencies: Bool,
                                targetsToFilter: [String]) throws -> GraphViz.Graph
    {
        let project = try modelLoader.loadProject(at: path)
        let (_, graph) = try graphLoader.loadProject(at: path, projects: [project])
        return graphToGraphVizMapper.map(
            graph: graph,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            targetsToFilter: targetsToFilter
        )
    }

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    public func generateWorkspace(at path: AbsolutePath,
                                  skipTestTargets: Bool,
                                  skipExternalDependencies: Bool,
                                  targetsToFilter: [String]) throws -> GraphViz.Graph
    {
        let workspace = try modelLoader.loadWorkspace(at: path)
        let projects = try workspace.projects.map(modelLoader.loadProject)
        let graph = try graphLoader.loadWorkspace(workspace: workspace, projects: projects)
        return graphToGraphVizMapper.map(
            graph: graph,
            skipTestTargets: skipTestTargets,
            skipExternalDependencies: skipExternalDependencies,
            targetsToFilter: targetsToFilter
        )
    }
}
