import Basic
import Foundation
import TuistSupport
@testable import TuistCore

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath, Versions) throws -> (Graph, Project))?
    public func loadProject(path: AbsolutePath, versions: Versions) throws -> (Graph, Project) {
        return try loadProjectStub?(path, versions) ?? (Graph.test(), Project.test())
    }

    public var loadWorkspaceStub: ((AbsolutePath, Versions) throws -> (Graph, Workspace))?
    public func loadWorkspace(path: AbsolutePath, versions: Versions) throws -> (Graph, Workspace) {
        return try loadWorkspaceStub?(path, versions) ?? (Graph.test(), Workspace.test())
    }

    public var loadConfigStub: ((AbsolutePath, Versions) throws -> (Config))?
    public func loadConfig(path: AbsolutePath, versions: Versions) throws -> Config {
        try loadConfigStub?(path, versions) ?? Config.test()
    }
}
