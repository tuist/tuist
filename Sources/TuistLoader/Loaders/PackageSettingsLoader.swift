import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Entity responsible for providing `PackageSettings`.
public protocol PackageSettingsLoading {
    /// Load the Dependencies model at the specified path.
    /// - Parameter path: The absolute path for the `PackageSettings` to load.
    /// - Parameter plugins: The plugins for the `PackageSettings` to load.
    /// - Returns: The `PackageSettings` loaded from the specified path.
    func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) throws -> TuistGraph.PackageSettings
}

public final class PackageSettingsLoader: PackageSettingsLoading {
    private let manifestLoader: ManifestLoading

    public init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }

    public func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) throws -> TuistGraph.PackageSettings {
        try manifestLoader.register(plugins: plugins)
        let manifest = try manifestLoader.loadPackageSettings(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)

        return try TuistGraph.PackageSettings.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )
    }
}
