import Foundation
import TSCBasic
import TuistCore
import XcodeProj
@testable import TuistGenerator

final class MockDescriptorGenerator: DescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateProjectSub: ((Project, Graph) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graph: Graph) throws -> ProjectDescriptor {
        guard let generateProjectSub = generateProjectSub else {
            throw MockError.stubNotImplemented
        }

        return try generateProjectSub(project, graph)
    }

    var generateWorkspaceStub: ((Workspace, Graph) throws -> WorkspaceDescriptor)?
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> WorkspaceDescriptor {
        guard let generateWorkspaceStub = generateWorkspaceStub else {
            throw MockError.stubNotImplemented
        }

        return try generateWorkspaceStub(workspace, graph)
    }
}
