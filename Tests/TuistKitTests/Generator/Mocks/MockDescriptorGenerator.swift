import Basic
import Foundation
import TuistCore
import XcodeProj
@testable import TuistGenerator

class MockDescriptorGenerator: DescriptorGenerating {
    var generateProjectSub: ((Project, Graph) throws -> GeneratedProjectDescriptor)?
    func generateProject(project: Project, graph: Graph) throws -> GeneratedProjectDescriptor {
        try generateProjectSub?(project, graph) ?? GeneratedProjectDescriptor.test()
    }

    var generateProjectWithConfigStub: ((Project, Graph, ProjectGenerationConfig) throws -> GeneratedProjectDescriptor)?
    func generateProject(project: Project, graph: Graph, config: ProjectGenerationConfig) throws -> GeneratedProjectDescriptor {
        try generateProjectWithConfigStub?(project, graph, config) ?? GeneratedProjectDescriptor.test()
    }

    var generateWorkspaceStub: ((Workspace, Graph) throws -> GeneratedWorkspaceDescriptor)?
    func generateWorkspace(workspace: Workspace, graph: Graph) throws -> GeneratedWorkspaceDescriptor {
        try generateWorkspaceStub?(workspace, graph) ?? GeneratedWorkspaceDescriptor.test()
    }
}
