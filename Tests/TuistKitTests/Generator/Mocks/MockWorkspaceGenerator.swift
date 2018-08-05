import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((AbsolutePath, Graphing, GenerationOptions, Systeming, Printing, ResourceLocating) throws -> Void)?

    func generate(path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  system: Systeming,
                  printer: Printing,
                  resourceLocator: ResourceLocating) throws {
        try generateStub?(path, graph, options, system, printer, resourceLocator)
    }
}
