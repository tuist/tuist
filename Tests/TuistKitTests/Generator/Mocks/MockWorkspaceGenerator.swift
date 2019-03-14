import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((WorkspaceStructure, AbsolutePath, Graphing, GenerationOptions, GenerationDirectory) throws -> AbsolutePath)?

    func generate(workspace: WorkspaceStructure, path: AbsolutePath, graph: Graphing, options: GenerationOptions, directory: GenerationDirectory) throws -> AbsolutePath {
        return (try generateStub?(workspace, path, graph, options, directory)) ?? AbsolutePath("/test")
    }
}
