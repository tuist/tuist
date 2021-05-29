import Foundation
import TSCBasic
import TuistGraph

public extension DependenciesGraph {
    static func test(
        nodes: [String: DependenciesGraphNode] = [:]
    ) -> Self {
        .init(
            nodes: nodes
        )
    }
}
