import Foundation
import TSCBasic

/// A directed acyclic graph (DAG) that Tuist uses to represent the third party dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies,
    /// and the values are the dependencies themselves.
    public var thirdPartyDependencies: [String: ThirdPartyDependency]

    /// Create an instance of `DependenciesGraph` model.
    public init(
        thirdPartyDependencies: [String: ThirdPartyDependency]
    ) {
        self.thirdPartyDependencies = thirdPartyDependencies
    }
}
