import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Entity responsible for loading the DependenciesGraph.
public protocol DependenciesGraphLoading {
    /// Load the DependenciesGraph at the specified path.
    /// - Parameter path: The absolute path for the dependency graph to load.
    func loadDependencies(at path: AbsolutePath) throws -> DependenciesGraph
}

public class DependenciesGraphLoader: DependenciesGraphLoading {
    public init() {}

    public func loadDependencies(at path: AbsolutePath) throws -> DependenciesGraph {
        guard FileHandler.shared.exists(path) else { return .none }
        return try JSONDecoder().decode(DependenciesGraph.self, from: try FileHandler.shared.readFile(path))
    }
}
