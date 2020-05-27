import Foundation
import TSCBasic

/// An directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct ValueGraph: Equatable {
    /// A dictionary where the keys are the paths to the directories where the projects are defined,
    /// and the values are the projects defined in the directories.
    public let projects: [AbsolutePath: Project]

    /// A dictionary where the keys are paths to the directories where the projects that contain packages are defined,
    /// and the values are dictionaries where the key is the reference to the package, and the values are the packages.
    public let packages: [AbsolutePath: [String: Package]]

    /// A dictionary where the keys are paths to the directories where the projects that contain targets are defined,
    /// and the values are dictionaries where the key is the name of the target, and the values are the targets.
    public let targets: [AbsolutePath: [String: Target]]

    /// A dictionary that contains the one-to-many dependencies that represent the graph.
    public let dependencies: [ValueGraphDependency: [ValueGraphDependency]]

    public init(projects: [AbsolutePath: Project],
                packages: [AbsolutePath: [String: Package]],
                targets: [AbsolutePath: [String: Target]],
                dependencies: [ValueGraphDependency: [ValueGraphDependency]]) {
        self.projects = projects
        self.packages = packages
        self.targets = targets
        self.dependencies = dependencies
    }
}
