import Foundation
import GraphViz
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader

extension GraphVizGenerating {
    func generate(
        at path: AbsolutePath,
        manifestLoader: ManifestLoading,
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        plugins: Plugins
    ) throws -> GraphViz.Graph {
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            return try generateWorkspace(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies, plugins: plugins)
        } else if manifests.contains(.project) {
            return try generateProject(at: path, skipTestTargets: skipTestTargets, skipExternalDependencies: skipExternalDependencies, plugins: plugins)
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }
}
