import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - Dependencies Graph Controller Errors

enum DependenciesGraphControllerError: FatalError, Equatable {
    case failedToDecodeDependenciesGraph
    case failedToEncodeDependenciesGraph

    var type: ErrorType {
        switch self {
        case .failedToDecodeDependenciesGraph:
            return .abort
        case .failedToEncodeDependenciesGraph:
            return .bug
        }
    }

    var description: String {
        switch self {
        case .failedToDecodeDependenciesGraph:
            return "Couldn't decode the DependenciesGraph from the serialized JSON file. Running `tuist fetch dependencies` should solve the problem."
        case .failedToEncodeDependenciesGraph:
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
    func save(_ dependenciesGraph: TuistGraph.DependenciesGraph, to path: AbsolutePath) throws

    /// Loads the `DependenciesGraph` from `graph.json` file.
    /// - Parameter path: Directory where project's dependencies graph will be loaded.
    func load(at path: AbsolutePath) throws -> TuistGraph.DependenciesGraph

    /// Removes cached `graph.json`.
    /// - Parameter path: Directory where project's dependencies graph was saved.
    func clean(at path: AbsolutePath) throws
}

// MARK: - Dependencies Graph Controller

public final class DependenciesGraphController: DependenciesGraphControlling {
    public init() {}

    public func save(_ dependenciesGraph: TuistGraph.DependenciesGraph, to path: AbsolutePath) throws {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted

        let encodedGraph = try jsonEncoder.encode(dependenciesGraph)

        guard let encodedGraphContent = String(data: encodedGraph, encoding: .utf8) else {
            throw DependenciesGraphControllerError.failedToEncodeDependenciesGraph
        }

        let graphPath = graphPath(at: path)

        try FileHandler.shared.touch(graphPath)
        try FileHandler.shared.write(encodedGraphContent, path: graphPath, atomically: true)
    }

    public func load(at path: AbsolutePath) throws -> TuistGraph.DependenciesGraph {
        let graphPath = graphPath(at: path)
        guard FileHandler.shared.exists(graphPath) else {
            return .none
        }
        let graphData = try FileHandler.shared.readFile(graphPath)

        do {
            return try JSONDecoder().decode(TuistGraph.DependenciesGraph.self, from: graphData)
        } catch {
            logger
                .debug(
                    "Failed to load dependencies graph, running `tuist fetch dependencies` should solve the problem.\nError: \(error)"
                )
            throw DependenciesGraphControllerError.failedToDecodeDependenciesGraph
        }
    }

    public func clean(at path: AbsolutePath) throws {
        let graphPath = graphPath(at: path)

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
