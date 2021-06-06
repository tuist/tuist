import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

/// A protocol that defines an interface to save and load the `DependenciesGraph` using a `graph.json` file.
public protocol DependenciesGraphControlling {
    /// Saves the `DependenciesGraph` as `graph.json`.
    /// - Parameters:
    ///   - dependenciesGraph: A model that will be saved.
    ///   - path: Directory where project's dependencies graph will be saved.
    func save(_ dependenciesGraph: DependenciesGraph, to path: AbsolutePath) throws

    /// Loads the `DependenciesGraph` from `graph.json` file.
    /// - Parameter path: Directory where project's dependencies graph will be loaded.
    func load(at path: AbsolutePath) throws -> DependenciesGraph
}

public final class DependenciesGraphController: DependenciesGraphControlling {
    public init() { }

    public func save(_ dependenciesGraph: DependenciesGraph, to path: AbsolutePath) throws {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        let encodedGraph = try jsonEncoder.encode(dependenciesGraph)
        #warning("WIP: handle force unwrapping better!")
        let encodedGraphContent = String(data: encodedGraph, encoding: .utf8)!
        let graphPath = self.graphPath(at: path)

        try FileHandler.shared.write(encodedGraphContent, path: graphPath, atomically: true)
    }

    public func load(at path: AbsolutePath) throws -> DependenciesGraph {
        let graphPath = graphPath(at: path)
        let graphData = try FileHandler.shared.readFile(graphPath)

        let jsonDecoder = JSONDecoder()
        let decodedGraph = try jsonDecoder.decode(DependenciesGraph.self, from: graphData)

        return decodedGraph
    }

    // MARK: - Helpers

    private func graphPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(components: [
                Constants.tuistDirectoryName,
                Constants.DependenciesDirectory.name,
                Constants.DependenciesDirectory.graphName
            ])
    }
}
