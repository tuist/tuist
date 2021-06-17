import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - Dependencies Graph Controller Errors

enum DependenciesGraphControllerError: FatalError, Equatable {
    case failedToEncodeDependeniesGraph

    var type: ErrorType {
        switch self {
        case .failedToEncodeDependeniesGraph:
            return .bug
        }
    }

    var description: String {
        switch self {
        case .failedToEncodeDependeniesGraph:
            return "Couldn't encode the DependenciesGraph as a JSON file."
        }
    }
}

// MARK: - Dependencies Graph Controlling

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

    /// Removes cached `graph.json`.
    /// - Parameter path: Directory where project's dependencies graph was saved.
    func clean(at path: AbsolutePath) throws
}

// MARK: - Dependencies Graph Controller

public final class DependenciesGraphController: DependenciesGraphControlling {
    public init() {}

    public func save(_ dependenciesGraph: DependenciesGraph, to path: AbsolutePath) throws {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        let encodedGraph = try jsonEncoder.encode(dependenciesGraph)

        guard let encodedGraphContent = String(data: encodedGraph, encoding: .utf8) else {
            throw DependenciesGraphControllerError.failedToEncodeDependeniesGraph
        }

        let graphPath = self.graphPath(at: path)

        try FileHandler.shared.touch(graphPath)
        try FileHandler.shared.write(encodedGraphContent, path: graphPath, atomically: true)
    }

    public func load(at path: AbsolutePath) throws -> DependenciesGraph {
        let graphPath = self.graphPath(at: path)
        let graphData = try FileHandler.shared.readFile(graphPath)

        let jsonDecoder = JSONDecoder()
        let decodedGraph = try jsonDecoder.decode(DependenciesGraph.self, from: graphData)

        return decodedGraph
    }

    public func clean(at path: AbsolutePath) throws {
        let graphPath = self.graphPath(at: path)

        try FileHandler.shared.delete(graphPath)
    }

    // MARK: - Helpers

    private func graphPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(components: [
                Constants.tuistDirectoryName,
                Constants.DependenciesDirectory.name,
                Constants.DependenciesDirectory.graphName,
            ])
    }
}
