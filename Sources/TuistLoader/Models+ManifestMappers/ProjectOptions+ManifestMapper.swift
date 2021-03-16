import Foundation
import TuistGraph
import ProjectDescription

extension TuistGraph.ProjectOptions {
    static func from(manifest: ProjectDescription.ProjectOptions,
                     generatorPaths: GeneratorPaths) throws -> TuistGraph.ProjectOptions {
        switch manifest {
        case .synthesizedResourceAccessors:
            return .synthesizedResourceAccessors
        }
    }
}
