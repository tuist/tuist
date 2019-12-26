import Basic
import TuistGenerator

extension Generating {
    public func generate(at path: AbsolutePath,
                         manifestLoader: ManifestLoading,
                         projectOnly: Bool) throws -> AbsolutePath {
        if projectOnly {
            return try generateProject(at: path)
        } else {
            return try generateWorkspace(at: path,
                                         manifestLoader: manifestLoader)
        }
    }
    
    public func generateWorkspace(at path: AbsolutePath,
                                  manifestLoader: ManifestLoading) throws -> AbsolutePath {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, workspaceFiles: [])
        } else if manifests.contains(.project) {
            return try generateProjectWorkspace(at: path, workspaceFiles: [])
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }
}
