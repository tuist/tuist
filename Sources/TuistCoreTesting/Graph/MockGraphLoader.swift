import Foundation
import TSCBasic
@testable import TuistCore

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath) throws -> (Graph, Project))?
    public func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        return try loadProjectStub?(path) ?? (Graph.test(), Project.test())
    }

    public var loadWorkspaceStub: ((AbsolutePath) throws -> (Graph))?
    public func loadWorkspace(path: AbsolutePath) throws -> (Graph) {
        return try loadWorkspaceStub?(path) ?? Graph.test()
    }

    public var loadConfigStub: ((AbsolutePath) throws -> (Config))?
    public func loadConfig(path: AbsolutePath) throws -> Config {
        try loadConfigStub?(path) ?? Config.test()
    }

    public var loadDependencyGraphStub: (([CarthageDependency], AbsolutePath) throws -> (DependencyGraph))?
    public func loadDependencyGraph(for dependencies: [CarthageDependency],
                                    atPath path: AbsolutePath) throws -> DependencyGraph {
        try loadDependencyGraphStub?(dependencies, path) ?? DependencyGraph.test()
    }
}
