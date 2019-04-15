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

    static func create(project: Project,
                       dependencies: [(target: Target, dependencies: [Target])]) -> Graph {
        let targetNodes = createTargetNodes(project: project, dependencies: dependencies)

        let cache = GraphLoaderCache()
        let graph = Graph.test(name: project.name,
                               entryPath: project.path,
                               cache: cache,
                               entryNodes: targetNodes)

        targetNodes.forEach { cache.add(targetNode: $0) }
        cache.add(project: project)

        return graph
    }

    private static func createTargetNodes(project: Project,
                                          dependencies: [(target: Target, dependencies: [Target])]) -> [TargetNode] {
        let nodesCache = Dictionary(uniqueKeysWithValues: dependencies.map {
            ($0.target.name, TargetNode(project: project,
                                        target: $0.target,
                                        dependencies: []))
        })

        dependencies.forEach {
            let node = nodesCache[$0.target.name]!
            node.dependencies = $0.dependencies.map { nodesCache[$0.name]! }
        }

        return dependencies.map { nodesCache[$0.target.name]! }
    }
}
