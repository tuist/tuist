import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolderException {
    static func from(
        manifest: ProjectDescription.BuildableFolderException,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let excluded = try manifest.excluded.map { try generatorPaths.resolve(path: $0) }
        let compilerFlags = Dictionary(uniqueKeysWithValues: try manifest.compilerFlags.map {
            (try generatorPaths.resolve(path: $0.0), $0.1)
        })
        return Self(excluded: excluded, compilerFlags: compilerFlags)
    }
}
