import Basic
import Foundation
@testable import TuistKit

class MockGenerator: Generating {
    var generateProjectStub: ((AbsolutePath, GeneratorConfig) throws -> AbsolutePath)?
    func generateProject(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath {
        return try generateProjectStub?(path, config) ?? AbsolutePath("/test")
    }

    var generateWorkspaceStub: ((AbsolutePath, GeneratorConfig) throws -> AbsolutePath)?
    func generateWorkspace(at path: AbsolutePath, config: GeneratorConfig) throws -> AbsolutePath {
        return try generateWorkspaceStub?(path, config) ?? AbsolutePath("/test")
    }
}
