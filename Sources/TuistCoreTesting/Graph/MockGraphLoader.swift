import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistGraphTesting

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
}
