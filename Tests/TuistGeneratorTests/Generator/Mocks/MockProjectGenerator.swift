import Basic
import Foundation
import TuistCore
@testable import TuistGenerator

final class MockProjectGenerator: ProjectGenerating {
    var generateStub: ((Project, Graphing, AbsolutePath?) throws -> GeneratedProject)?

    func generate(project: Project,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?) throws -> GeneratedProject {
        return try generateStub?(project, graph, sourceRootPath) ?? GeneratedProject.test()
    }
}
