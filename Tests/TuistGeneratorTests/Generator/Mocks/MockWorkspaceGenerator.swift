import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateWorkspaces: [Workspace] = []
    var generateStub: ((Workspace, AbsolutePath, Graphing) throws -> WorkspaceDescriptor)?

    func generate(workspace: Workspace, path: AbsolutePath, graph: Graphing) throws -> WorkspaceDescriptor {
        generateWorkspaces.append(workspace)
        return try generateStub?(workspace, path, graph) ?? stub
    }

    private var stub: WorkspaceDescriptor {
        WorkspaceDescriptor(path: "/test",
                            xcworkspace: XCWorkspace(),
                            projects: [],
                            schemes: [],
                            sideEffects: [])
    }
}
