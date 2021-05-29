import Foundation
import TSCBasic

/// A directed acyclic graph (DAG) that Tuist uses to represent the third party dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies,
    /// and the values are the dependencies itself.
    public var nodes: [String: DependenciesGraphNode]

    /// Create an instance of `DependenciesGraph` model.
    public init(
        nodes: [String: DependenciesGraphNode]
    ) {
        self.nodes = nodes
    }
}
