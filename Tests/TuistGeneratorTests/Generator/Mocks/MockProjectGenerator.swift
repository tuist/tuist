import Basic
import Foundation
import TuistCore
@testable import TuistGenerator

final class MockProjectGenerator: ProjectGenerating {
    var generatedProjects: [Project] = []
    var generateStub: ((Project, Graphing, AbsolutePath?) throws -> GeneratedProject)?

    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?,
                  xcodeProjName _: String) throws -> GeneratedProject {
        generatedProjects.append(project)
        return try generateStub?(project, graph, sourceRootPath) ?? GeneratedProject.test()
    }
}
