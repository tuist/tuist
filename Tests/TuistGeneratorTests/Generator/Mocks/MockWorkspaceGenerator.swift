import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Workspace, AbsolutePath, Graphable, TuistConfig) throws -> AbsolutePath)?

    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphable,
                  tuistConfig: TuistConfig) throws -> AbsolutePath {
        generateWorkspaces.append(workspace)
        return (try generateStub?(workspace, path, graph, tuistConfig)) ?? AbsolutePath("/test")
    }
}
