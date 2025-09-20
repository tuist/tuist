import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderExceptions {
    static func from(
        manifest: ProjectDescription.BuildableFolderExceptions,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        return Self(exceptions: try manifest.exceptions.map {
            try XcodeGraph.BuildableFolderException.from(manifest: $0, generatorPaths: generatorPaths)
        })
    }
}
