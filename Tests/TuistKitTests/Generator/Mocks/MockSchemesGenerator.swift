import Foundation
@testable import TuistKit

final class MockSchemesGenerator: SchemesGenerating {
    var generateTargetSchemesArgs: [(project: Project, generatedProject: GeneratedProject)] = []
    var generateProjectSchemeArgs: [(project: Project, generatedProject: GeneratedProject, graph: Graphing)] = []

    func generateTargetSchemes(project: Project, generatedProject: GeneratedProject) throws {
        generateTargetSchemesArgs.append((project: project, generatedProject: generatedProject))
    }
    
    func generateProjectScheme(project: Project, generatedProject: GeneratedProject, graph: Graphing) throws {
        generateProjectSchemeArgs.append((project: project, generatedProject: generatedProject, graph: graph))
    }
}
