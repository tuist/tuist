import Basic
import Foundation
import TuistCore
import TuistGenerator
import TuistLoader

extension Generator {
    /// Initializes a generator instance with all the dependencies that are specific to Tuist.
    convenience init() {
        let manifestLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader, manifestLinter: manifestLinter)
        self.init(modelLoader: modelLoader)
    }
}

extension Generating {
    func generate(at path: AbsolutePath,
                  manifestLoader: ManifestLoading,
                  projectOnly: Bool) throws -> (AbsolutePath, Graphing) {
        if projectOnly {
            return try generateProject(at: path)
        } else {
            return try generateWorkspace(at: path,
                                         manifestLoader: manifestLoader)
        }
    }

    func generateWorkspace(at path: AbsolutePath,
                           manifestLoader: ManifestLoading) throws -> (AbsolutePath, Graphing) {
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
