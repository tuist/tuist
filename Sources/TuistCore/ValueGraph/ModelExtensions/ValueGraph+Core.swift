import TSCBasic
import TuistGraph

public extension ValueGraph {
    init(graph: Graph) {
        let name = graph.name
        let path = graph.entryPath
        let workspace = graph.workspace
        let projects = graph.projects.reduce(into: [AbsolutePath: Project]()) { $0[$1.path] = $1 }
        let packages = graph.packages.reduce(into: [AbsolutePath: [String: Package]]()) { acc, package in
            var packages = acc[package.path, default: [:]]
            packages[package.name] = package.package
            acc[package.path] = packages
        }
        let targets = graph.targets.mapValues { targets in targets.reduce(into: [String: Target]()) { $0[$1.name] = $1.target } }
        let dependencies = ValueGraph.dependencies(from: graph)
        self.init(
            name: name,
            path: path,
            workspace: workspace,
            projects: projects,
            packages: packages,
            targets: targets,
            dependencies: dependencies
        )
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
            frameworkNode.dependencies.forEach { nodeDependencies.formUnion([self.dependency(from: $0.node)]) }
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
            return .framework(
                path: node.path,
                binaryPath: node.binaryPath,
                dsymPath: node.dsymPath,
                bcsymbolmapPaths: node.bcsymbolmapPaths,
                linking: node.linking,
                architectures: node.architectures,
                isCarthage: node.isCarthage
            )
        case let node as XCFrameworkNode:
            return .xcframework(
                path: node.path,
                infoPlist: node.infoPlist,
                primaryBinaryPath: node.primaryBinaryPath,
                linking: node.linking
            )
        case let node as LibraryNode:
            return .library(
                path: node.path,
                publicHeaders: node.publicHeaders,
                linking: node.linking,
                architectures: node.architectures,
                swiftModuleMap: node.swiftModuleMap
            )
        case let node as PackageProductNode:
            return .packageProduct(path: node.path, product: node.product)
        case let node as SDKNode:
            return .sdk(
                name: node.name,
                path: node.path,
                status: node.status,
                source: node.source
            )
        case let node as PackageProductNode:
            return .packageProduct(
                path: node.path,
                product: node.product
            )
        case let node as CocoaPodsNode:
            return .cocoapods(path: node.path)
        default:
            fatalError("Unsupported dependency node type")
        }
    }
}
