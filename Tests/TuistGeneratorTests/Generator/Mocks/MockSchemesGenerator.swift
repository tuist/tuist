import Foundation
import Basic
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockSchemesGenerator: SchemesGenerating {
    var generateProjectSchemeArgs: [(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphing)] = []
    
    func generateProjectSchemes(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphing) throws {
        generateProjectSchemeArgs.append((project: project, xcprojectPath: xcprojectPath, generatedProject: generatedProject, graph: graph))
    }
}
