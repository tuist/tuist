import Foundation
import GraphViz
import TSCBasic
import TuistGenerator
import TuistLoader

extension GraphVizGenerating {
    func generate(at path: AbsolutePath,
                  manifestLoader: ManifestLoading,
                  skipTestTargets: Bool,
                  skipExternalDependencies: Bool) throws -> GraphViz.Graph {
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies)
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }
}
