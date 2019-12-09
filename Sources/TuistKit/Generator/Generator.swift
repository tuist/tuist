import Basic
import TuistGenerator

extension Generating {
    func generate(at path: AbsolutePath,
                  manifestLoader: GraphManifestLoading,
                  projectOnly: Bool) throws -> AbsolutePath {
        if projectOnly {
            return try generateProject(at: path)
        } else {
            return try generateWorkspace(at: path,
                                         manifestLoader: manifestLoader)
        }
    }

    func generateWorkspace(at path: AbsolutePath,
                           manifestLoader: GraphManifestLoading) throws -> AbsolutePath {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, workspaceFiles: [])
        } else if manifests.contains(.project) {
            return try generateProjectWorkspace(at: path, workspaceFiles: [])
        } else {
            throw GraphManifestLoaderError.manifestNotFound(path)
        }
    }
}
