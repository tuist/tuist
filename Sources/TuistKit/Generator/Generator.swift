import Basic
import TuistGenerator

extension Generating {
    func generate(at path: AbsolutePath,
                  manifestLoader: GraphManifestLoading) throws -> AbsolutePath {
        let manifests = manifestLoader.manifests(at: path)
        let workspaceFiles: [AbsolutePath] = [Manifest.workspace, Manifest.setup]
            .compactMap { try? manifestLoader.manifestPath(at: path, manifest: $0) }

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, workspaceFiles: workspaceFiles)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, workspaceFiles: workspaceFiles)
        } else {
            throw GraphManifestLoaderError.manifestNotFound(path)
        }
    }
}
