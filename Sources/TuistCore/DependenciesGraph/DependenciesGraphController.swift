import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// A protocol that defines an interface to save and load the `DependenciesGraph` using a `graph.json` file.
public protocol DependenciesGraphControlling {
    /// Saves the `DependenciesGraph` as `graph.json`.
    /// - Parameters:
    ///   - dependenciesGraph: A model that will be saved.
    ///   - path: Directory whose project's dependencies graph will be saved.
    func save(_ dependenciesGraph: DependenciesGraph, at path: AbsolutePath) throws
    
    /// Loads the `DependenciesGraph` from `graph.json` file.
    /// - Parameter path: Directory whose project's dependencies graph will be loaded.
    func load(at path: AbsolutePath) throws -> DependenciesGraph
}

public final class DependenciesGraphController: DependenciesGraphControlling {
    private let fileHandler: FileHandling
    
    public init(
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.fileHandler = fileHandler
    }
    
    public func save(_ dependenciesGraph: DependenciesGraph, at path: AbsolutePath) throws {
        let jsonEncoder = JSONEncoder()
        let encodedGraph = try jsonEncoder
            .encode(dependenciesGraph)
            .base64EncodedString()

        let graphPath = graphPath(at: path)
        
        try fileHandler.write(encodedGraph, path: graphPath, atomically: true)
    }
    
    public func load(at path: AbsolutePath) throws -> DependenciesGraph {
        let graphPath = graphPath(at: path)
        let graphData =  try fileHandler.readFile(graphPath)
        
        let jsonDecoder = JSONDecoder()
        let decodedGraph = try jsonDecoder.decode(DependenciesGraph.self, from: graphData)
        
        return decodedGraph
    }
    
    // MARK: - Helpers
    
    private func graphPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
            .appending(component: Constants.DependenciesDirectory.graphName)
    }
}
