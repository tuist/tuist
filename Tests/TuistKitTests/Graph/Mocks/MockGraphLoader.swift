import Basic
import Foundation
@testable import TuistKit

final class MockGraphLoader: GraphLoading {
    var loadProjectStub: ((AbsolutePath) throws -> (WorkspaceStructure, Graph))?
    func loadProject(path: AbsolutePath) throws -> (WorkspaceStructure, Graph) {
        return try loadProjectStub?(path) ?? (WorkspaceStructure(name: "name", contents: [ ]), Graph.test())
    }

    var loadWorkspaceStub: ((AbsolutePath) throws -> (WorkspaceStructure, Graph))?
    func loadWorkspace(path: AbsolutePath) throws -> (WorkspaceStructure, Graph) {
        return try loadWorkspaceStub?(path) ?? (WorkspaceStructure(name: "name", contents: [ ]), Graph.test())
    }
}
