import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistGraphTesting

public final class MockValueGraphLoader: ValueGraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath, [Project]) throws -> (Project, ValueGraph))?
    public func loadProject(at path: AbsolutePath, projects: [Project]) throws -> (Project, ValueGraph) {
        return try loadProjectStub?(path, projects) ?? (Project.test(), ValueGraph.test())
    }

    public var loadWorkspaceStub: ((Workspace, [Project]) throws -> (ValueGraph))?
    public func loadWorkspace(workspace: Workspace, projects: [Project]) throws -> ValueGraph {
        return try loadWorkspaceStub?(workspace, projects) ?? ValueGraph.test()
    }
}
