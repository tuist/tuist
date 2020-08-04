import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol DotGraphGenerating {
    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    func generateProject(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    func generateWorkspace(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String
}

public final class DotGraphGenerator: DotGraphGenerating {
    /// Graph loader.
    private let graphLoader: GraphLoading

    /// Mapper to map graphs into a dot graphs.
    private let graphToDotGraphMapper: GraphToDotGraphMapping

    /// Initializes the dot graph generator by taking its dependencies.
    ///
    /// - Parameters:
    ///   - modelLoader: Instance to load the models.
    public convenience init(modelLoader: GeneratorModelLoading) {
        let graphLoader = GraphLoader(modelLoader: modelLoader)
        self.init(graphLoader: graphLoader, graphToDotGraphMapper: GraphToDotGraphMapper())
    }

    /// Initializes the generator with an instance to load the graph.
    ///
    /// - Parameters:
    ///   - graphLoader: Graph loader instance.
    ///   - graphToDotGraphMapper: Mapper to map the graph into a dot graph.
    init(graphLoader: GraphLoading,
         graphToDotGraphMapper: GraphToDotGraphMapping)
    {
        self.graphLoader = graphLoader
        self.graphToDotGraphMapper = graphToDotGraphMapper
    }

    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    public func generateProject(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String {
        let (graph, _) = try graphLoader.loadProject(path: path)
        return graphToDotGraphMapper.map(graph: graph, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies).description
    }

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    public func generateWorkspace(at path: AbsolutePath, skipTestTargets: Bool, skipExternalDependencies: Bool) throws -> String {
        let (graph, _) = try graphLoader.loadWorkspace(path: path)
        return graphToDotGraphMapper.map(graph: graph, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies).description
    }
}
