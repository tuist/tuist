import TSCBasic
import TuistSupport

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {

    /// A dictionary where the keys are the supported platforms and the values are dictionaries where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let externalDependencies: ExternalDependencies

    /// A dictionary where the keys are the folder of external projects, and the values are the projects themselves.
    public let externalProjects: [AbsolutePath: Project]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: ExternalDependencies, externalProjects: [AbsolutePath: Project]) {
        self.externalDependencies = externalDependencies
        self.externalProjects = externalProjects
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:], externalProjects: [:])
}

// MARK: ExternalDependencies
extension DependenciesGraph {

    /// Type representation of external dependencies keyed by platform to target names and then the targets themselves
    public typealias ExternalDependencies = [Platform: [String: [TargetDependency]]]
}

extension DependenciesGraph.ExternalDependencies {

    /// Flag to indigate whether external dependencies handle multiple platforms
    public var hasMultiplePlatforms: Bool {
        return self.keys.count > 1
    }
}
