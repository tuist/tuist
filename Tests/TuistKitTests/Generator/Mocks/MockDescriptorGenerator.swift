import Basic
import Foundation
import TuistCore
import XcodeProj
@testable import TuistGenerator

class MockDescriptorGenerator: DescriptorGenerating {
    var generateProjectSub: ((Project, Graph) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graph: Graph) throws -> ProjectDescriptor {
        try generateProjectSub?(project, graph) ?? ProjectDescriptor.test()
    }

    var generateProjectWithConfigStub: ((Project, Graph, ProjectGenerationConfig) throws -> ProjectDescriptor)?
    func generateProject(project: Project, graph: Graph, config: ProjectGenerationConfig) throws -> ProjectDescriptor {
        try generateProjectWithConfigStub?(project, graph, config) ?? ProjectDescriptor.test()
    }

    var generateWorkspaceStub: ((Workspace, Graph) throws -> WorkspaceDescriptor)?
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> WorkspaceDescriptor {
        try generateWorkspaceStub?(workspace, graph) ?? WorkspaceDescriptor.test()
    }
}
