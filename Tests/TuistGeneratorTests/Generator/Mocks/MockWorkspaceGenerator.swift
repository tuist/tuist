import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Workspace, AbsolutePath, Graphing) throws -> GeneratedWorkspaceDescriptor)?

    func generate(workspace: Workspace, path: AbsolutePath, graph: Graphing) throws -> GeneratedWorkspaceDescriptor {
        generateWorkspaces.append(workspace)
        return try generateStub?(workspace, path, graph) ?? stub
    }

    private var stub: GeneratedWorkspaceDescriptor {
        GeneratedWorkspaceDescriptor(path: "/test",
                                     xcworkspace: XCWorkspace(),
                                     projects: [],
                                     schemes: [],
                                     sideEffects: [])
    }
}
