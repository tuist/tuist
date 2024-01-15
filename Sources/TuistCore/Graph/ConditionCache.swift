import Foundation
import TuistGraph
import TuistSupport

/// Cache designed to store `PlatformCondition.CombinationResult` for `GraphTraverser`
final class ConditionCache {
    private final class ConditionCacheValue {
        let conditionResult: PlatformCondition.CombinationResult
        init(conditionResult: PlatformCondition.CombinationResult) {
            self.conditionResult = conditionResult
        }
    }

    private final class GraphEdgeCacheKey: NSObject {
        let edge: GraphEdge
        init(_ edge: GraphEdge) {
            self.edge = edge
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Self else {
                return false
            }

            return edge == other.edge
        }

        override var hash: Int {
            edge.hashValue
        }
    }

    private let cache = NSCache<GraphEdgeCacheKey, ConditionCacheValue>()

    public subscript(_ edge: (GraphDependency, GraphDependency)) -> PlatformCondition.CombinationResult? {
        get {
            cache.object(forKey: GraphEdgeCacheKey(GraphEdge(from: edge.0, to: edge.1)))?.conditionResult
        }
        set {
            if let newValue {
                cache.setObject(
                    ConditionCacheValue(conditionResult: newValue),
                    forKey: GraphEdgeCacheKey(GraphEdge(from: edge.0, to: edge.1))
                )
            } else {
                cache.removeObject(forKey: GraphEdgeCacheKey(GraphEdge(from: edge.0, to: edge.1)))
            }
        }
    }
}
