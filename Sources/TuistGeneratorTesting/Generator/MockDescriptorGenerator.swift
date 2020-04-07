import Basic
import Foundation
import TuistCore
import TuistSupport
import XcodeProj
@testable import TuistGenerator

final class MockDescriptorGenerator: DescriptorGenerating {
    enum MockError: Error {
        case stubNotImplemented
    }

    var generateProjectSub: ((Project, Graph, Versions) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graph: Graph, versions: Versions) throws -> ProjectDescriptor {
        guard let generateProjectSub = generateProjectSub else {
            throw MockError.stubNotImplemented
        }

        return try generateProjectSub(project, graph, versions)
    }

    var generateProjectWithConfigStub: ((Project, Graph, ProjectGenerationConfig) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graph: Graph, config: ProjectGenerationConfig, versions _: Versions) throws -> ProjectDescriptor {
        guard let generateProjectWithConfigStub = generateProjectWithConfigStub else {
            throw MockError.stubNotImplemented
        }

        return try generateProjectWithConfigStub(project, graph, config)
    }

    var generateWorkspaceStub: ((Workspace, Graph) throws -> WorkspaceDescriptor)?
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> WorkspaceDescriptor {
        guard let generateWorkspaceStub = generateWorkspaceStub else {
            throw MockError.stubNotImplemented
        }

        return try generateWorkspaceStub(workspace, graph)
    }
}
