import Foundation
import TSCBasic
import TuistGraph
import TuistSupport
import TuistCore

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
    private let rootDirectoryLocator: RootDirectoryLocating

    /// Default constructor.
    public init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()) {
        self.rootDirectoryLocator = rootDirectoryLocator
    }

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
        var graphPath = graphPath(at: path)

        if !FileHandler.shared.exists(graphPath) {
            // If the current directory does not have a dependency graph available
            // look at the root of the complete project
            
            guard let rootDirectory = self.rootDirectoryLocator.locate(from: path) else {
                return .none
            }
            let rootGraphPath = self.graphPath(at: rootDirectory)
            
            guard FileHandler.shared.exists(rootGraphPath) else {
                return .none
            }
            
            graphPath = rootGraphPath
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
