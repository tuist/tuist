import Basic
import Foundation
@testable import TuistKit

final class MockGraphLoader: GraphLoading {
    var loadProjectStub: ((AbsolutePath) throws -> Graph)?
    func loadProject(path: AbsolutePath) throws -> Graph {
        return try loadProjectStub?(path) ?? Graph.test()
    }

    var loadWorkspaceStub: ((AbsolutePath) throws -> Graph)?
    func loadWorkspace(path: AbsolutePath) throws -> Graph {
        return try loadWorkspaceStub?(path) ?? Graph.test()
    }
}
