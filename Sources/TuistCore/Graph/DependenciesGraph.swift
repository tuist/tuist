import ProjectDescription
import TuistSupport

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct DependenciesGraph: Equatable, Codable {
    public struct ExternalProject: Equatable, Codable {
        public let project: Project
        public let type: PackageType

        public init(project: Project, type: PackageType) {
            self.project = project
            self.type = type
        }
    }

    /// A dictionary of Platforms to a dictionary where the keys are the names of dependencies, and the values are the
    /// dependencies themselves.
    public let externalDependencies: [String: [TargetDependency]]

    /// A dictionary where the keys are the folder of external projects, and the values are the model for the projects themselves.
    public let externalProjects: [Path: ExternalProject]

    /// Create an instance of `DependenciesGraph` model.
    public init(externalDependencies: [String: [TargetDependency]], externalProjects: [Path: ExternalProject]) {
        self.externalDependencies = externalDependencies
        self.externalProjects = externalProjects
    }

    /// An empty `DependenciesGraph`.
    public static let none: DependenciesGraph = .init(externalDependencies: [:], externalProjects: [:])
}
