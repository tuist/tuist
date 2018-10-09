import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((AbsolutePath, Graphing, GenerationOptions, GenerationDirectory) throws -> AbsolutePath)?

    func generate(path: AbsolutePath, graph: Graphing, options: GenerationOptions, directory: GenerationDirectory) throws -> AbsolutePath {
        return (try generateStub?(path, graph, options, directory)) ?? AbsolutePath("/test")
    }
}
