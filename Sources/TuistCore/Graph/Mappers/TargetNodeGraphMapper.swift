import Basic
import Foundation

/// Target Node Graph Mapper
///
/// A `GraphMapper` that allows transforming `TargetNode`s without modifying
/// the original nodes. Additionally, any projects associated with orphaned nodes after
/// any transformations will no longer be part of the resulting graph.
///
/// - Note: When mapping, the `transform` block receives a copy of the original `TargetNode`
open class TargetNodeGraphMapper: GraphMapping {
    public let mapTargetNode: (TargetNode) -> (TargetNode, [SideEffectDescriptor])
    public init(transform: @escaping (TargetNode) -> (TargetNode, [SideEffectDescriptor])) {
        mapTargetNode = transform
    }

    // MARK: - GraphMapping

    public func map(graph: Graph) -> (Graph, [SideEffectDescriptor]) {
        var mappedCache = [GraphNodeMapKey: GraphNode]()
        let cache = GraphLoaderCache()

        var sideEffects: [SideEffectDescriptor] = []
        let updatedNodes = graph.entryNodes.map { (targetNode) -> GraphNode in
            let (mappedNode, mappedSideEffects) = map(node: targetNode, mappedCache: &mappedCache, cache: cache)
            sideEffects.append(contentsOf: mappedSideEffects)
            return mappedNode
        }

        return (Graph(name: graph.name,
                      entryPath: graph.entryPath,
                      cache: cache,
                      entryNodes: updatedNodes), [])
    }

    // MARK: - Private

    private func map(node: GraphNode,
                     mappedCache: inout [GraphNodeMapKey: GraphNode],
                     cache: GraphLoaderCache) -> (GraphNode, [SideEffectDescriptor]) {
        if let cached = mappedCache[node.mapperCacheKey] {
            return (cached, [])
        }

        switch node {
        case let packageProductNode as PackageProductNode:
            cache.add(package: packageProductNode)
            return (packageProductNode, [])
        case let precompiledNode as PrecompiledNode:
            cache.add(precompiledNode: precompiledNode)
            return (precompiledNode, [])
        case let cocoapodsNode as CocoaPodsNode:
            cache.add(cocoapods: cocoapodsNode)
            return (cocoapodsNode, [])
        case let targetNode as TargetNode:
            let (updated, sideEffects) = map(targetNode: targetNode,
                                             mappedCache: &mappedCache,
                                             cache: cache)
            cache.add(targetNode: updated)
            cache.add(project: updated.project)
            return (updated, sideEffects)
        default:
            fatalError("Unhandled graph node type")
        }
    }

    private func map(targetNode: TargetNode,
                     mappedCache: inout [GraphNodeMapKey: GraphNode],
                     cache: GraphLoaderCache) -> (TargetNode, [SideEffectDescriptor]) {
        var updated = TargetNode(project: targetNode.project,
                                 target: targetNode.target,
                                 dependencies: targetNode.dependencies)
        var sideEffects: [SideEffectDescriptor]
        (updated, sideEffects) = mapTargetNode(updated)
        mappedCache[updated.mapperCacheKey] = updated

        updated.dependencies = updated.dependencies.map {
            let (mappedDependency, mappedSideEffects) = map(node: $0, mappedCache: &mappedCache, cache: cache)
            sideEffects.append(contentsOf: mappedSideEffects)
            return mappedDependency
        }

        return (updated, sideEffects)
    }
}

private struct GraphNodeMapKey: Hashable {
    var name: String
    var path: AbsolutePath
}

private extension GraphNode {
    var mapperCacheKey: GraphNodeMapKey {
        .init(name: name, path: path)
    }
}
