import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockProjectGenerator: ProjectGenerating {
    var generateStub: ((Project, GenerationOptions, Graphing, AbsolutePath?) throws -> GeneratedProject)?

    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?) throws -> GeneratedProject {
        return try generateStub?(project, options, graph, sourceRootPath) ?? GeneratedProject.test()
    }
}
