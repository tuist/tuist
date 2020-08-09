import Foundation
import TSCBasic
@testable import TuistCore

public extension Graph {
    static func test(name: String = "test",
                     entryPath: AbsolutePath = AbsolutePath("/test/graph"),
                     entryNodes: [GraphNode] = [],
                     projects: [Project] = [],
                     cocoapods: [CocoaPodsNode] = [],
                     packages: [PackageNode] = [],
                     precompiled: [PrecompiledNode] = [],
                     targets: [AbsolutePath: [TargetNode]] = [:]) -> Graph
    {
        Graph(name: name,
              entryPath: entryPath,
              entryNodes: entryNodes,
              projects: projects,
              cocoapods: cocoapods,
              packages: packages,
              precompiled: precompiled,
              targets: targets)
    }

    /// Creates a test dependency graph for targets within a single project
    ///
    /// Note: For the purposes of testing, to reduce complexity of resolving dependencies
    ///       The `dependencies` property is used to define the dependencies explicitly.
    ///       All targets need to be listed even if they don't have any dependencies.
    static func create(project: Project,
                       dependencies: [(target: Target, dependencies: [Target])],
                       packages: [PackageNode] = []) -> Graph
    {
        create(project: project,
               entryNodes: dependencies.map(\.target),
               dependencies: dependencies,
               packages: packages)
    }

    static func create(project: Project,
                       entryNodes: [Target],
                       dependencies: [(target: Target, dependencies: [Target])],
                       packages: [PackageNode] = []) -> Graph
    {
        let dependenciesWithProject = dependencies.map { (
            project: project,
            target: $0.target,
            dependencies: $0.dependencies
        ) }
        let targetNodes = createTargetNodes(dependencies: dependenciesWithProject)

        let entryNodes = entryNodes.compactMap { entryNode in
            targetNodes.first { $0.name == entryNode.name }
        }

        let targets = targetNodes.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, next in
            var dict = acc[next.path, default: []]
            dict.append(next)
            acc[next.path] = dict
        }
        let graph = Graph.test(name: project.name,
                               entryPath: project.path,
                               entryNodes: entryNodes,
                               projects: [project],
                               packages: packages,
                               targets: targets)

        return graph
    }

    /// Creates a test dependency graph for targets within a multiple projects
    ///
    /// Note: For the purposes of testing, to reduce complexity of resolving dependencies
    ///       The `dependencies` property is used to define the dependencies explicitly.
    ///       All targets need to be listed even if they don't have any dependencies.
    static func create(projects: [Project] = [],
                       entryNodes: [Target]? = nil,
                       dependencies: [(project: Project, target: Target, dependencies: [Target])]) -> Graph
    { // swiftlint:disable:this large_tuple
        let targetNodes = createTargetNodes(dependencies: dependencies)

        let entryNodes = entryNodes.map { entryNodes in
            entryNodes.compactMap { entryNode in
                targetNodes.first { $0.name == entryNode.name }
            }
        }

        let targets = targetNodes.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, next in
            var dict = acc[next.path, default: []]
            dict.append(next)
            acc[next.path] = dict
        }

        let graph = Graph.test(name: projects.first?.name ?? "Test",
                               entryPath: projects.first?.path ?? AbsolutePath("/test/path"),
                               entryNodes: entryNodes ?? targetNodes,
                               projects: projects,
                               targets: targets)

        return graph
    }

    // swiftlint:disable:next large_tuple
    private static func createTargetNodes(dependencies: [(project: Project, target: Target, dependencies: [Target])]) -> [TargetNode] {
        let nodesCache = Dictionary(uniqueKeysWithValues: dependencies.map {
            ($0.target.name, TargetNode(project: $0.project,
                                        target: $0.target,
                                        dependencies: []))
        })

        dependencies.forEach {
            let node = nodesCache[$0.target.name]!
            let platform = $0.target.platform
            node.dependencies = $0.dependencies.map { nodesCache[$0.name]! }
            let sdkDependencies: [(name: String, status: SDKStatus)] = $0.target.dependencies.compactMap {
                if case let .sdk(name: name, status: status) = $0 {
                    return (name: name, status: status)
                }
                return nil
            }
            node.dependencies.append(contentsOf: sdkDependencies.compactMap {
                try? SDKNode(name: $0.name, platform: platform, status: $0.status, source: .developer)
            })
            let packageDependencies: [String] = $0.target.dependencies.compactMap {
                if case let .package(packageType) = $0 {
                    return packageType
                }
                return nil
            }
            node.dependencies.append(contentsOf: packageDependencies.map {
                PackageProductNode(product: $0, path: node.path)
            })
        }

        return dependencies.map { nodesCache[$0.target.name]! }
    }
}
