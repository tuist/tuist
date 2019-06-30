import Basic
import Foundation
import TuistGenerator

extension DotGraphGenerating {
    func generate(at path: AbsolutePath,
                  manifestLoader: GraphManifestLoading) throws -> String {
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path)
        } else if manifests.contains(.project) {
            return try generateProject(at: path)
        } else {
            throw GraphManifestLoaderError.manifestNotFound(path)
        }
    }
}
