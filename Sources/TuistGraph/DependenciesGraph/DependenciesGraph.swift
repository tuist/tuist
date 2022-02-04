import TSCBasic
import TuistSupport

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let externalDependencies: [String: [TargetDependency]]

    /// A dictionary where the keys are the folder of external projects, and the values are the projects themselves.
    public let externalProjects: [AbsolutePath: Project]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: [TargetDependency]], externalProjects: [AbsolutePath: Project]) {
        self.externalDependencies = externalDependencies
        self.externalProjects = externalProjects
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:], externalProjects: [:])
}
