import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((Workspace, AbsolutePath, Graphing, GenerationOptions, GenerationDirectory) throws -> AbsolutePath)?

    func generate(workspace: Workspace,
                  path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  directory: GenerationDirectory) throws -> AbsolutePath {
        return (try generateStub?(workspace, path, graph, options, directory)) ?? AbsolutePath("/test")
    }
}
