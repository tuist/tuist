import Foundation
import TSCBasic
@testable import TuistCore

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath, Plugins) throws -> (Graph, Project))?
    public func loadProject(path: AbsolutePath, plugins: Plugins) throws -> (Graph, Project) {
        return try loadProjectStub?(path, plugins) ?? (Graph.test(), Project.test())
    }

    public var loadWorkspaceStub: ((AbsolutePath, Plugins) throws -> (Graph))?
    public func loadWorkspace(path: AbsolutePath, plugins: Plugins) throws -> (Graph) {
        return try loadWorkspaceStub?(path, plugins) ?? Graph.test()
    }

    public var loadConfigStub: ((AbsolutePath) throws -> (Config))?
    public func loadConfig(path: AbsolutePath) throws -> Config {
        try loadConfigStub?(path) ?? Config.test()
    }
}
