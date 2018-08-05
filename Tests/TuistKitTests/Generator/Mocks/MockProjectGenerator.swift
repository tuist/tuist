import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockProjectGenerator: ProjectGenerating {
    var generateStub: ((Project, GenerationOptions, Graphing, AbsolutePath?, Systeming, Printing, ResourceLocating) throws -> AbsolutePath)?

    func generate(project: Project,
                  options: GenerationOptions,
                  graph: Graphing,
                  sourceRootPath: AbsolutePath?,
                  system: Systeming,
                  printer: Printing,
                  resourceLocator: ResourceLocating) throws -> AbsolutePath {
        return try generateStub?(project, options, graph, sourceRootPath, system, printer, resourceLocator) ?? AbsolutePath("/")
    }
}
