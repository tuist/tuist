import Basic
import Foundation
@testable import TuistCore

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath) throws -> (Graph, Project))?
    public func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        return try loadProjectStub?(path) ?? (Graph.test(), Project.test())
    }

    public var loadWorkspaceStub: ((AbsolutePath) throws -> (Graph, Workspace))?
    public func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace) {
        return try loadWorkspaceStub?(path) ?? (Graph.test(), Workspace.test())
    }

    public var loadTuistConfigStub: ((AbsolutePath) throws -> (TuistConfig))?
    public func loadTuistConfig(path: AbsolutePath) throws -> TuistConfig {
        return try loadTuistConfigStub?(path) ?? TuistConfig.test()
    }
}
