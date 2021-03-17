import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.ProjectOptions {
    static func from(manifest: ProjectDescription.ProjectOptions,
                     generatorPaths _: GeneratorPaths) throws -> TuistGraph.ProjectOptions
    {
        switch manifest {
        case .synthesizedResourceAccessors:
            return .synthesizedResourceAccessors
        }
    }
}
