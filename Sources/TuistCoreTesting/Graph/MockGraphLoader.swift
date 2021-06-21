import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistGraphTesting

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath, [Project]) throws -> (Project, Graph))?
    public func loadProject(at path: AbsolutePath, projects: [Project]) throws -> (Project, Graph) {
        return try loadProjectStub?(path, projects) ?? (Project.test(), Graph.test())
    }

    public var loadWorkspaceStub: ((Workspace, [Project]) throws -> (Graph))?
    public func loadWorkspace(workspace: Workspace, projects: [Project]) throws -> Graph {
        return try loadWorkspaceStub?(workspace, projects) ?? Graph.test()
    }
}
