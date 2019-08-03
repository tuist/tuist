import Basic
import Foundation
@testable import TuistGenerator

extension Graph {
    static func test(name: String = "test",
                     entryPath: AbsolutePath = AbsolutePath("/test/graph"),
                     cache: GraphLoaderCaching = GraphLoaderCache(),
                     entryNodes: [GraphNode] = []) -> Graph {
        return Graph(name: name,
                     entryPath: entryPath,
                     cache: cache,
                     entryNodes: entryNodes)
    }

    /// Creates a test dependency graph for targets within a single project
    ///
    /// Note: For the purposes of testing, to reduce complexity of resolving dependencies
    ///       The `dependencies` property is used to define the dependencies explicitly.
    ///       All targets need to be listed even if they don't have any dependencies.
    static func create(project: Project,
                       dependencies: [(target: Target, dependencies: [Target])]) -> Graph {
        let depenenciesWithProject = dependencies.map { (
            project: project,
            target: $0.target,
            dependencies: $0.dependencies
        ) }
        let targetNodes = createTargetNodes(dependencies: depenenciesWithProject)

        let cache = GraphLoaderCache()
        let graph = Graph.test(name: project.name,
                               entryPath: project.path,
                               cache: cache,
                               entryNodes: targetNodes)

        targetNodes.forEach { cache.add(targetNode: $0) }
        cache.add(project: project)

        return graph
    }

    /// Creates a test dependency graph for targets within a multiple projects
    ///
    /// Note: For the purposes of testing, to reduce complexity of resolving dependencies
    ///       The `dependencies` property is used to define the dependencies explicitly.
    ///       All targets need to be listed even if they don't have any dependencies.
    static func create(projects: [Project] = [],
                       entryNodes: [Target]? = nil,
                       dependencies: [(project: Project, target: Target, dependencies: [Target])]) -> Graph {
        let targetNodes = createTargetNodes(dependencies: dependencies)

        let entryNodes = entryNodes.map { entryNodes in
            targetNodes.filter { entryNodes.contains($0.target) }
        }

        let cache = GraphLoaderCache()
        let graph = Graph.test(name: projects.first?.name ?? "Test",
                               entryPath: projects.first?.path ?? "/test/path",
                               cache: cache,
                               entryNodes: entryNodes ?? targetNodes)

        targetNodes.forEach { cache.add(targetNode: $0) }
        projects.forEach { cache.add(project: $0) }

        return graph
    }

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
                try? SDKNode(name: $0.name, platform: platform, status: $0.status)
            })
        }

        return dependencies.map { nodesCache[$0.target.name]! }
    }
}
