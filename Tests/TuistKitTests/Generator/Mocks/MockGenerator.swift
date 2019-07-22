import Basic
import Foundation
import TuistGenerator

class MockGenerator: Generating {
    var generateProjectStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateProject(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateProjectStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }

    var generateWorkspaceStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateWorkspaceStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }
}
