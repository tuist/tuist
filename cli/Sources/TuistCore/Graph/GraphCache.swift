import Foundation
import XcodeGraph

final class GraphCache<Key: Hashable, Value> {
    private final class CacheValue {
        let value: Value
        init(_ value: Value) {
            self.value = value
        }
    }

    private final class CacheKey: NSObject {
        let key: Key
        init(_ key: Key) {
            self.key = key
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Self else {
                return false
            }

            return key == other.key
        }

        override var hash: Int {
            key.hashValue
        }
    }

    private let cache = NSCache<CacheKey, CacheValue>()

    subscript(_ key: Key) -> Value? {
        get {
            cache.object(forKey: CacheKey(key))?.value
        }
        set {
            if let newValue {
                cache.setObject(
                    CacheValue(newValue),
                    forKey: CacheKey(key)
                )
            } else {
                cache.removeObject(forKey: CacheKey(key))
            }
        }
    }
}

/// Cache designed to store `PlatformCondition.CombinationResult` for `GraphTraverser`
typealias ConditionCache = GraphCache<GraphEdge, PlatformCondition.CombinationResult>

extension ConditionCache {
    subscript(_ edge: (GraphDependency, GraphDependency)) -> Value? {
        get {
            self[GraphEdge(from: edge.0, to: edge.1)]
        }
        set {
            if let newValue {
                cache.setObject(
                    CacheValue(newValue),
                    forKey: CacheKey(GraphEdge(from: edge.0, to: edge.1))
                )
            } else {
                cache.removeObject(forKey: CacheKey(GraphEdge(from: edge.0, to: edge.1)))
            }
        }
    }
}
