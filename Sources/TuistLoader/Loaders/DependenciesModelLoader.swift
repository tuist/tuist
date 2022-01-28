import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Entity responsible for providing dependencies model.
public protocol DependenciesModelLoading {
    /// Load the Dependencies model at the specified path.
    /// - Parameter path: The absolute path for the dependency models to load.
    /// - Parameter plugins: The plugins for the dependency models to load.
    /// - Returns: The Dependencies loaded from the specified path.
    /// - Throws: Error encountered during the loading process (e.g. Missing Dependencies file).
    func loadDependencies(at path: AbsolutePath, with plugins: Plugins) throws -> TuistGraph.Dependencies
}

public class DependenciesModelLoader: DependenciesModelLoading {
    private let manifestLoader: ManifestLoading

    public init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }

    public func loadDependencies(at path: AbsolutePath, with plugins: Plugins) throws -> TuistGraph.Dependencies {
        try manifestLoader.register(plugins: plugins)
        let manifest = try manifestLoader.loadDependencies(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)

        return try TuistGraph.Dependencies.from(manifest: manifest, generatorPaths: generatorPaths)
    }
}
