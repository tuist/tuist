import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

/// Entity responsible for providing dependencies model.
public protocol DependenciesServicing {
    /// Load the Dependencies model at the specified path.
    /// - Parameters
    ///     - path: The absolute path for the dependency models to load.
    ///     - config: The Tuist config manifest to load (for plugins).
    /// - Returns: The Dependencies loaded from the specified path.
    /// - Throws: Error encountered during the loading process (e.g. Missing Dependencies file).
    func loadDependencies(at path: AbsolutePath, using config: TuistGraph.Config) throws -> TuistGraph.Dependencies
}

public class DependenciesService: DependenciesServicing {
    private let manifestLoader: ManifestLoading
    private let pluginService: PluginServicing

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        pluginService: PluginServicing = PluginService()
    ) {
        self.manifestLoader = manifestLoader
        self.pluginService = pluginService
    }

    public func loadDependencies(at path: AbsolutePath, using config: TuistGraph.Config) throws -> TuistGraph.Dependencies {
        let plugins = try pluginService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)
        let manifest = try manifestLoader.loadDependencies(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try TuistGraph.Dependencies.from(manifest: manifest, generatorPaths: generatorPaths)
    }
}
