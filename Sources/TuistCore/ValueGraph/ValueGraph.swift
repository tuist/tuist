import Foundation
import TSCBasic

/// An directed acyclic graph (DAG) that Tuist uses to represent the dependency tree.
public struct ValueGraph: Equatable {
    /// The name of the graph
    public let name: String

    /// The path where the graph has been loaded from.
    public let path: AbsolutePath

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
    public let dependencies: [ValueGraphDependency: Set<ValueGraphDependency>]

    public init(name: String,
                path: AbsolutePath,
                projects: [AbsolutePath: Project],
                packages: [AbsolutePath: [String: Package]],
                targets: [AbsolutePath: [String: Target]],
                dependencies: [ValueGraphDependency: Set<ValueGraphDependency>])
    {
        self.name = name
        self.path = path
        self.projects = projects
        self.packages = packages
        self.targets = targets
        self.dependencies = dependencies
    }

    public init(graph: Graph) {
        name = graph.name
        path = graph.entryPath
        projects = graph.projects.reduce(into: [AbsolutePath: Project]()) { $0[$1.path] = $1 }
        packages = graph.packages.reduce(into: [AbsolutePath: [String: Package]]()) { acc, package in
            var packages = acc[package.path, default: [:]]
            packages[package.name] = package.package
            acc[package.path] = packages
        }
        targets = graph.targets.mapValues { targets in targets.reduce(into: [String: Target]()) { $0[$1.name] = $1.target } }
        dependencies = ValueGraph.dependencies(from: graph)
    }

    /// Given a graph loader cache, it returns a dictionary representing the dependency tree.
    /// - Parameter cache: Cache generated after loading the projects.
    /// - Returns: Dependency tree.
    private static func dependencies(from graph: Graph) -> [ValueGraphDependency: Set<ValueGraphDependency>] {
        var dependencies: [ValueGraphDependency: Set<ValueGraphDependency>] = [:]
        graph.forEach { map(node: $0, into: &dependencies) }
        return dependencies
    }

    /// Traverses the node and its dependencies and adds them to the dependencies dictionary.
    /// - Parameters:
    ///   - node: Node whose dependencies will be mapped.
    ///   - dependencies: Dictionary containing the dependency tree.
    private static func map(node: GraphNode, into dependencies: inout [ValueGraphDependency: Set<ValueGraphDependency>]) {
        let nodeDependency = dependency(from: node)
        var nodeDependencies: Set<ValueGraphDependency>! = dependencies[nodeDependency, default: Set()]

        if let targetNode = node as? TargetNode {
            targetNode.dependencies.forEach { nodeDependencies.formUnion([self.dependency(from: $0)]) }
        } else if let frameworkNode = node as? FrameworkNode {
            frameworkNode.dependencies.forEach { nodeDependencies.formUnion([self.dependency(from: $0)]) }
        } else if let xcframeworkNode = node as? XCFrameworkNode {
            xcframeworkNode.dependencies.forEach { nodeDependencies.formUnion([self.dependency(from: $0.node)]) }
        }
        dependencies[nodeDependency] = nodeDependencies
    }

    /// Given a graph node, it returns its value representation.
    /// - Parameter node: Graph node.
    /// - Returns: Value-type representation.
    private static func dependency(from node: GraphNode) -> ValueGraphDependency {
        switch node {
        case let node as TargetNode:
            return .target(name: node.name, path: node.path)
        case let node as FrameworkNode:
            return .framework(path: node.path,
                              dsymPath: node.dsymPath,
                              bcsymbolmapPaths: node.bcsymbolmapPaths,
                              linking: node.linking,
                              architectures: node.architectures)
        case let node as XCFrameworkNode:
            return .xcframework(path: node.path,
                                infoPlist: node.infoPlist,
                                primaryBinaryPath: node.primaryBinaryPath,
                                linking: node.linking)
        case let node as LibraryNode:
            return .library(path: node.path,
                            publicHeaders: node.publicHeaders,
                            linking: node.linking,
                            architectures: node.architectures,
                            swiftModuleMap: node.swiftModuleMap)
        case let node as PackageProductNode:
            return .packageProduct(path: node.path, product: node.product)
        case let node as SDKNode:
            return .sdk(name: node.name,
                        path: node.path,
                        status: node.status,
                        source: node.source)
        case let node as PackageProductNode:
            return .packageProduct(path: node.path,
                                   product: node.product)
        case let node as CocoaPodsNode:
            return .cocoapods(path: node.path)
        default:
            fatalError("Unsupported dependency node type")
        }
    }
}
