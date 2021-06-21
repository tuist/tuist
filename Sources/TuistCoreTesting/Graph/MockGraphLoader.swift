import Foundation
import TSCBasic
import TuistCore
import TuistGraph
@testable import TuistGraphTesting

public final class MockGraphLoader: GraphLoading {
    public init() {}

    public var loadProjectStub: ((AbsolutePath, [Project], DependenciesGraph) throws -> (Project, Graph))?
    public func loadProject(at path: AbsolutePath, projects: [Project], dependencies: DependenciesGraph) throws -> (Project, Graph) {
        return try loadProjectStub?(path, projects, dependencies) ?? (Project.test(), Graph.test())
    }

    public var loadWorkspaceStub: ((Workspace, [Project], DependenciesGraph) throws -> (Graph))?
    public func loadWorkspace(workspace: Workspace, projects: [Project], dependencies: DependenciesGraph) throws -> Graph {
        return try loadWorkspaceStub?(workspace, projects, dependencies) ?? Graph.test()
    }
}
