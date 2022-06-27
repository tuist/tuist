import ProjectDescription

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    /// A dictionary of Platforms to a dictionary where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let externalDependencies: [Platform: [String: [TargetDependency]]]

    /// A dictionary where the keys are the supported platforms and the values are dictionaries where the keys are the names of dependencies, and the values are the dependencies themselves.
    public let externalProjects: [Path: Project]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [Platform: [String: [TargetDependency]]], externalProjects: [Path: Project]) {
        self.externalDependencies = externalDependencies
        self.externalProjects = externalProjects
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:], externalProjects: [:])
}
