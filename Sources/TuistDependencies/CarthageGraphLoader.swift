import Foundation
import TuistCore
import ProjectDescription
import TSCBasic

enum CarthageGraphLoadingError: Error {
    case wrongManager
}

protocol CarthageGraphLoading {
//    func load(dependencies: ProjectDescription.Dependencies, atPath path: AbsolutePath) throws -> DependencyGraph
}

struct CarthageGraphLoader {

//    func load(dependencies: ProjectDescription.Dependencies, atPath path: AbsolutePath) throws -> DependencyGraph {
//        try load(dependencies: dependencies.dependencies.filter { $0.manager == .carthage }, atPath: path)
//    }
//
//    func load(dependencies: [ProjectDescription.Dependency], atPath path: AbsolutePath) throws -> DependencyGraph {
//        DependencyGraph(entryNodes: dependencies.map { load(dependency: $0) })
//    }
////
//    private func load(dependency: ProjectDescription.Dependency) -> GraphNode {
//
//    }
}

struct DependencyGraph {
    /// The entry nodes of the graph.
    public let entryNodes: [GraphNode]
}
