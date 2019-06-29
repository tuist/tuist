import Basic
import Foundation
import TuistCore

public protocol DotGraphGenerating {
    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    func generateProject(at path: AbsolutePath) throws -> String

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    func generateWorkspace(at path: AbsolutePath) throws -> String
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
    ///   - system: Instance to run commands in the system.
    ///   - printer: Instance to print outputs to the user.
    ///   - fileHandler: Instance to handle files.
    public convenience init(modelLoader: GeneratorModelLoading,
                            system _: Systeming = System(),
                            printer: Printing = Printer(),
                            fileHandler: FileHandling = FileHandler()) {
        let graphLinter = GraphLinter(fileHandler: fileHandler)
        let graphLoader = GraphLoader(linter: graphLinter, printer: printer, fileHandler: fileHandler, modelLoader: modelLoader)
        self.init(graphLoader: graphLoader)
    }

    /// Initializes the generator with an instance to load the graph.
    ///
    /// - Parameter graphLoader: Graph loader instance.
    init(graphLoader: GraphLoading,
         graphToDotGraphMapper: GraphToDotGraphMapping = GraphToDotGraphMapper()) {
        self.graphLoader = graphLoader
        self.graphToDotGraphMapper = graphToDotGraphMapper
    }

    /// Generates the dot graph from the project in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the project.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the project can't be loaded.
    public func generateProject(at path: AbsolutePath) throws -> String {
        let (graph, _) = try graphLoader.loadProject(path: path)
        return graphToDotGraphMapper.map(graph: graph).description
    }

    /// Generates the dot graph from the workspace in the current directory and returns it.
    ///
    /// - Parameter path: Path to the folder that contains the workspace.
    /// - Returns: Dot graph representation.
    /// - Throws: An error if the workspace can't be loaded.
    public func generateWorkspace(at path: AbsolutePath) throws -> String {
        let (graph, _) = try graphLoader.loadWorkspace(path: path)
        return graphToDotGraphMapper.map(graph: graph).description
    }
}
