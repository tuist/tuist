import Basic
import Foundation
import TuistGenerator

class MockGenerator: Generating {
    var generateProjectStub: ((AbsolutePath, GeneratorConfig, [AbsolutePath]) throws -> AbsolutePath)?
    func generateProject(at path: AbsolutePath, config: GeneratorConfig, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateProjectStub?(path, config, workspaceFiles) ?? AbsolutePath("/test")
    }

    var generateWorkspaceStub: ((AbsolutePath, GeneratorConfig, [AbsolutePath]) throws -> AbsolutePath)?
    func generateWorkspace(at path: AbsolutePath, config: GeneratorConfig, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateWorkspaceStub?(path, config, workspaceFiles) ?? AbsolutePath("/test")
    }
}
