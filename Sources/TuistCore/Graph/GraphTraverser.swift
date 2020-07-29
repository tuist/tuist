//
// Created by kwridan on 7/29/20.
//

import Foundation
import TSCBasic

public final class GraphTraverser: GraphTraversing {
    private let graph: Graph
    public init(graph: Graph) {
        self.graph = graph
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> [Target] {
        graph.targetDependencies(path: path, name: name).map { $0.target }
    }

    public func appExtensionDependencies(path: AbsolutePath, name: String) -> [Target] {
        graph.appExtensionDependencies(path: path, name: name).map { $0.target }
    }

    public func resourceBundleDependencies(path: AbsolutePath, name: String) -> [Target] {
        graph.resourceBundleDependencies(path: path, name: name).map { $0.target }
    }
}
