import Foundation
import TSCBasic

/// A directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct Graph: Equatable, Codable {
    /// The name of the graph
    public var name: String

    /// The path where the graph has been loaded from.
    public var path: AbsolutePath

    /// Graph's workspace.
    public var workspace: Workspace

    /// A dictionary where the keys are the paths to the directories where the projects are defined,
    /// and the values are the projects defined in the directories.
    public var projects: [AbsolutePath: Project]

    /// A dictionary where the keys are paths to the directories where the projects that contain packages are defined,
    /// and the values are dictionaries where the key is the reference to the package, and the values are the packages.
    public var packages: [AbsolutePath: [String: Package]]

    /// A dictionary where the keys are paths to the directories where the projects that contain targets are defined,
    /// and the values are dictionaries where the key is the name of the target, and the values are the targets.
    public var targets: [AbsolutePath: [String: Target]]

    /// A dictionary that contains the one-to-many dependencies that represent the graph.
    public var dependencies: [GraphDependency: Set<GraphDependency>]

    public init(
        name: String,
        path: AbsolutePath,
        workspace: Workspace,
        projects: [AbsolutePath: Project],
        packages: [AbsolutePath: [String: Package]],
        targets: [AbsolutePath: [String: Target]],
        dependencies: [GraphDependency: Set<GraphDependency>]
    ) {
        self.name = name
        self.path = path
        self.workspace = workspace
        self.projects = projects
        self.packages = packages
        self.targets = targets
        self.dependencies = dependencies
    }
}
