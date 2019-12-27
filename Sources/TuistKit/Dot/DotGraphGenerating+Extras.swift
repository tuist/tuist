import Basic
import Foundation
import TuistGenerator
import TuistLoader

extension DotGraphGenerating {
    func generate(at path: AbsolutePath,
                  manifestLoader: ManifestLoading) throws -> String {
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path)
        } else if manifests.contains(.project) {
            return try generateProject(at: path)
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }
}
