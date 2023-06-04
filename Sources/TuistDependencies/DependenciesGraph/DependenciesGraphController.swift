import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Dependencies Graph Controller Errors

enum DependenciesGraphControllerError: FatalError, Equatable {
    case failedToDecodeDependenciesGraph
    case failedToEncodeDependenciesGraph
    /// Thrown when there is a `Dependencies.swift` but no `graph.json`
    case dependenciesWerentFetched

    var type: ErrorType {
        switch self {
        case .dependenciesWerentFetched, .failedToDecodeDependenciesGraph:
            return .abort
        case .failedToEncodeDependenciesGraph:
            return .bug
        }
    }

    var description: String {
        switch self {
        case .dependenciesWerentFetched:
            return "`Tuist/Dependencies.swift` file is defined but `Tuist/Dependencies/graph.json` cannot be found. Run `tuist fetch` first"
        case .failedToDecodeDependenciesGraph:
            return "Couldn't decode the DependenciesGraph from the serialized JSON file. Running `tuist fetch` should solve the problem."
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
        // Search for the dependency graph at the root directory
        // This can be the directory of this project or in case of nested projects
        // the root of the overall project
        guard let rootDirectory = rootDirectoryLocator.locate(from: path) else {
            return .none
        }

        let dependenciesPath = dependenciesPath(at: rootDirectory)

        guard FileHandler.shared.exists(dependenciesPath) else {
            return .none
        }

        let rootGraphPath = graphPath(at: rootDirectory)

        guard FileHandler.shared.exists(rootGraphPath) else {
            throw DependenciesGraphControllerError.dependenciesWerentFetched
        }

        let graphData = try FileHandler.shared.readFile(rootGraphPath)

        do {
            return try JSONDecoder().decode(TuistGraph.DependenciesGraph.self, from: graphData)
        } catch {
            logger
                .debug(
                    "Failed to load dependencies graph, running `tuist fetch` should solve the problem.\nError: \(error)"
                )
            throw DependenciesGraphControllerError.failedToDecodeDependenciesGraph
        }
    }

    public func clean(at path: AbsolutePath) throws {
        let graphPath = graphPath(at: path)

        try FileHandler.shared.delete(graphPath)
    }

    // MARK: - Helpers

    private func dependenciesPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(components: [
                Constants.tuistDirectoryName,
                Constants.DependenciesDirectory.dependenciesFileName,
            ])
    }

    private func graphPath(at path: AbsolutePath) -> AbsolutePath {
        path
            .appending(components: [
                Constants.tuistDirectoryName,
                Constants.DependenciesDirectory.name,
                Constants.DependenciesDirectory.graphName,
            ])
    }
}
