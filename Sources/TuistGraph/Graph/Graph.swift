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

    /// A dictionary that contains the one-to-many dependencies that represent the graph.
    public var dependencies: [GraphDependency: Set<GraphDependency>]

    /// A dictionary that contains the Conditions to apply to a dependency relationship
    public var dependencyConditions: [GraphEdge: PlatformCondition]

    public init(
        name: String,
        path: AbsolutePath,
        workspace: Workspace,
        projects: [AbsolutePath: Project],
        packages: [AbsolutePath: [String: Package]],
        dependencies: [GraphDependency: Set<GraphDependency>],
        dependencyConditions: [GraphEdge: PlatformCondition]
    ) {
        self.name = name
        self.path = path
        self.workspace = workspace
        self.projects = projects
        self.packages = packages
        self.dependencies = dependencies
        self.dependencyConditions = dependencyConditions
    }
}

/// Convenience accessors to work with `GraphTarget` and `GraphDependency` types while traversing the graph
extension [GraphEdge: PlatformCondition] {
    public subscript(_ edge: (GraphDependency, GraphDependency)) -> PlatformCondition? {
        get {
            self[GraphEdge(from: edge.0, to: edge.1)]
        }
        set {
            self[GraphEdge(from: edge.0, to: edge.1)] = newValue
        }
    }

    public subscript(_ edge: (GraphDependency, GraphTarget)) -> PlatformCondition? {
        get {
            self[GraphEdge(from: edge.0, to: edge.1)]
        }
        set {
            self[GraphEdge(from: edge.0, to: edge.1)] = newValue
        }
    }
}
