import Foundation
import TSCBasic

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies, and the values are the dependencies themselves.
    public var externalDependencies: [String: ExternalDependency]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: ExternalDependency]) {
        self.externalDependencies = externalDependencies
    }
}
