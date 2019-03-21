import Basic
import Foundation
@testable import TuistKit

final class MockGraphLoader: GraphLoading {
    var loadProjectStub: ((AbsolutePath) throws -> (Graph, Project))?
    func loadProject(path: AbsolutePath) throws -> (Graph, Project) {
        return try loadProjectStub?(path) ?? (Graph.test(), Project.test())
    }

    var loadWorkspaceStub: ((AbsolutePath) throws -> (Graph, Workspace))?
    func loadWorkspace(path: AbsolutePath) throws -> (Graph, Workspace) {
        return try loadWorkspaceStub?(path) ?? (Graph.test(), Workspace.test())
    }
}
