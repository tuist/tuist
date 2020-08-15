import Foundation
import TSCBasic

public final class GraphTraverser: GraphTraversing {
    private let graph: Graph
    public init(graph: Graph) {
        self.graph = graph
    }

    public func target(path: AbsolutePath, name: String) -> Target? {
        graph.target(path: path, name: name).map(\.target)
    }

    public func targets(at path: AbsolutePath) -> [Target] {
        graph.targets(at: path).map(\.target)
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

    public func testTargetsDependingOn(path: AbsolutePath, name: String) -> [Target] {
        graph.testTargetsDependingOn(path: path, name: name).map(\.target)
    }

    public func directStaticDependencies(path: AbsolutePath, name: String) -> [GraphDependencyReference] {
        graph.staticDependencies(path: path, name: name)
    }
}
