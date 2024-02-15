import Foundation
import ProjectDescription
import TSCBasic
import TSCUtility
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
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileHandler: FileHandling

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.manifestLoader = manifestLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileHandler = fileHandler
    }

    public func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) throws -> TuistGraph.PackageSettings {
        let path = rootDirectoryLocator.locate(from: path) ?? path
        try manifestLoader.register(plugins: plugins)
        let manifest = try manifestLoader.loadPackageSettings(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let swiftToolsVersion = try swiftPackageManagerController.getToolsVersion(
            at: path
        )

        return try TuistGraph.PackageSettings.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            swiftToolsVersion: swiftToolsVersion
        )
    }
}
