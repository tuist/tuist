import Foundation
import Basic
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockSchemesGenerator: SchemesGenerating {
    
    var generateWorkspaceSchemeArgs: [(workspace: Workspace, xcworkspacePath: AbsolutePath, generatedProjects: [AbsolutePath: GeneratedProject], graph: Graphing)] = []
    
    var generateProjectSchemeArgs: [(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphing)] = []
    
    
    
    func generateWorkspaceSchemes(workspace: Workspace,
                                  xcworkspacePath: AbsolutePath,
                                  generatedProjects: [AbsolutePath: GeneratedProject],
                                  graph: Graphing) throws {
        generateWorkspaceSchemeArgs.append((workspace: workspace, xcworkspacePath: xcworkspacePath, generatedProjects: generatedProjects, graph: graph))
    }
    
    func generateProjectSchemes(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphing) throws {
        generateProjectSchemeArgs.append((project: project, xcprojectPath: xcprojectPath, generatedProject: generatedProject, graph: graph))
    }
    
    func wipeSchemes(at: AbsolutePath) throws { }
}
