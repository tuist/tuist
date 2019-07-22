import Basic
import Foundation
import TuistCore
@testable import TuistGenerator

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Workspace, AbsolutePath, Graphing) throws -> AbsolutePath)?

    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing) throws -> AbsolutePath {
        generateWorkspaces.append(workspace)
        return (try generateStub?(workspace, path, graph)) ?? AbsolutePath("/test")
    }
}
