import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildableFolder {
    static func from(
        manifest: ProjectDescription.BuildableFolder,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.BuildableFolder {
        return XcodeGraph.BuildableFolder(path: try generatorPaths.resolve(path: manifest.path))
    }
}
