import Basic
import TuistCore
import TuistLoader

extension GraphLoading {
    func load(at path: AbsolutePath, manifestLoader: ManifestLoading) throws -> Graph {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try loadWorkspace(path: path).0
        } else if manifests.contains(.project) {
            return try loadProject(path: path).0
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }
}
