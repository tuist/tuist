import Basic
import Foundation
import TuistCore
@testable import TuistKit

final class MockWorkspaceGenerator: WorkspaceGenerating {
    var generateStub: ((AbsolutePath, Graphing, GenerationOptions, Systeming, Printing, ResourceLocating) throws -> AbsolutePath)?

    func generate(path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  system: Systeming,
                  printer: Printing,
                  resourceLocator: ResourceLocating) throws -> AbsolutePath {
        return (try generateStub?(path, graph, options, system, printer, resourceLocator)) ?? AbsolutePath("/test")
    }
}
