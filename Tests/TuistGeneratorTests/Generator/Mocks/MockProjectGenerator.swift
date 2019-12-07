import Basic
import Foundation
import TuistCore
import TuistCoreTesting
import TuistSupport
@testable import TuistGenerator

final class MockProjectGenerator: ProjectGenerating {
    var generatedProjects: [Project] = []
    var generateStub: ((Project, Graphable, AbsolutePath?) throws -> GeneratedProject)?

    func generate(project: Project,
                  graph: Graphable,
                  sourceRootPath: AbsolutePath?) throws -> GeneratedProject {
        generatedProjects.append(project)
        return try generateStub?(project, graph, sourceRootPath) ?? GeneratedProject.test()
    }
}
