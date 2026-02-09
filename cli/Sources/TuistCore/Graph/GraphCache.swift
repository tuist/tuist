import Foundation
import TuistSupport
import TuistThreadSafe
import XcodeGraph

final class GraphCache<Key: Hashable, Value> {
    private let storage = ThreadSafe<[Key: Value]>([:])

    subscript(_ key: Key) -> Value? {
        get {
            storage.withValue { $0[key] }
        }
        set {
            storage.mutate { $0[key] = newValue }
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
            self[GraphEdge(from: edge.0, to: edge.1)] = newValue
        }
    }
}
