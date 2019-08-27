import Basic
import Foundation
import TuistGenerator

class MockGenerator: Generating {
    var generateProjectStub: ((AbsolutePath) throws -> AbsolutePath)?
    func generateProject(at path: AbsolutePath) throws -> AbsolutePath {
        return try generateProjectStub?(path) ?? AbsolutePath("/test")
    }

    var generateProjectWorkspaceStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateProjectWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateProjectWorkspaceStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }

    var generateWorkspaceStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        return try generateWorkspaceStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }
}
