import Basic
import Foundation
import TuistCore
import TuistGenerator

class MockGenerator: Generating {
    var generateProjectAtStub: ((AbsolutePath) throws -> AbsolutePath)?
    func generateProject(at path: AbsolutePath) throws -> AbsolutePath {
        try generateProjectAtStub?(path) ?? AbsolutePath("/test")
    }

    var generateProjectStub: ((Project, AbsolutePath?, AbsolutePath?) throws -> AbsolutePath)?
    func generateProject(_ project: Project, graph _: Graphing, sourceRootPath: AbsolutePath?, xcodeprojPath: AbsolutePath?) throws -> AbsolutePath {
        try generateProjectStub?(project, sourceRootPath, xcodeprojPath) ?? AbsolutePath("/test")
    }

    var generateProjectWorkspaceStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateProjectWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        try generateProjectWorkspaceStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }

    var generateWorkspaceStub: ((AbsolutePath, [AbsolutePath]) throws -> AbsolutePath)?
    func generateWorkspace(at path: AbsolutePath, workspaceFiles: [AbsolutePath]) throws -> AbsolutePath {
        try generateWorkspaceStub?(path, workspaceFiles) ?? AbsolutePath("/test")
    }
}
