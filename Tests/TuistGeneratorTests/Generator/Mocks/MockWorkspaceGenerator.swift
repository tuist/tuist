import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockWorkspaceGenerator: WorkspaceGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Workspace, AbsolutePath, Graph) throws -> WorkspaceDescriptor)?

    func generate(workspace: Workspace, path: AbsolutePath, graph: Graph) throws -> WorkspaceDescriptor {
        guard let generateStub = generateStub else {
            throw MockError.stubNotImplemented
        }
        generateWorkspaces.append(workspace)
        return try generateStub(workspace, path, graph)
    }
}
