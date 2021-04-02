import Foundation
import TSCBasic

/// A model that represents a node in the Swift Package Manager resolved dependency graph.
public struct PackageDependency: Equatable, Codable, Hashable {
    public let name: String
    public let url: String
    public let version: String
    public let path: String
    public let dependencies: [PackageDependency]
}

// MARK: - Helpers

extension PackageDependency {
    /// Returns path as `AbsolutePath`.
    var absolutePath: AbsolutePath {
        AbsolutePath(path)
    }

    /// Returns flatted unique dependencies.
    public func uniqueDependencies() -> Set<PackageDependency> {
        dependencies.reduce(into: [self]) { result, dependency in
            if !result.contains(dependency) {
                result.formUnion(dependency.uniqueDependencies())
            }
        }
    }
}
