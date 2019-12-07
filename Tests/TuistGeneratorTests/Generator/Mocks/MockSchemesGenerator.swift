import Basic
import Foundation
import TuistCore
import TuistCoreTesting
@testable import TuistGenerator

final class MockSchemesGenerator: SchemesGenerating {
    var generateProjectSchemeArgs: [(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphable)] = []

    func generateProjectSchemes(project: Project, xcprojectPath: AbsolutePath, generatedProject: GeneratedProject, graph: Graphable) throws {
        generateProjectSchemeArgs.append((project: project, xcprojectPath: xcprojectPath, generatedProject: generatedProject, graph: graph))
    }
}
