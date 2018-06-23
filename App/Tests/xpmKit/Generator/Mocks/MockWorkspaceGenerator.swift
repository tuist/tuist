import Basic
import Foundation
@testable import xpmKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((AbsolutePath, GeneratorContexting, GenerationOptions) throws -> Void)?

    func generate(path: AbsolutePath,
                  context: GeneratorContexting,
                  options: GenerationOptions) throws {
        try generateStub?(path, context, options)
    }
}
