import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph

/// Entity responsible for providing `PackageSettings`.
public protocol PackageSettingsLoading {
    /// Load the Dependencies model at the specified path.
    /// - Parameter path: The absolute path for the `PackageSettings` to load.
    /// - Parameter plugins: The plugins for the `PackageSettings` to load.
    /// - Returns: The `PackageSettings` loaded from the specified path.
    func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) async throws -> TuistCore.PackageSettings
}

public final class PackageSettingsLoader: PackageSettingsLoading {
    private let manifestLoader: ManifestLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let fileHandler: FileHandling
    private let manifestFilesLocator: ManifestFilesLocating

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(
            system: System.shared,
            fileHandler: FileHandler.shared
        ),
        fileHandler: FileHandling = FileHandler.shared,
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.manifestLoader = manifestLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.fileHandler = fileHandler
        self.manifestFilesLocator = manifestFilesLocator
    }

    public func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) async throws -> TuistCore.PackageSettings {
        let path = manifestFilesLocator.locatePackageManifest(at: path)?.parentDirectory ?? path
        try manifestLoader.register(plugins: plugins)
        let manifest = try await manifestLoader.loadPackageSettings(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        let swiftToolsVersion = try swiftPackageManagerController.getToolsVersion(
            at: path
        )

        return try TuistCore.PackageSettings.from(
            manifest: manifest,
            generatorPaths: generatorPaths,
            swiftToolsVersion: swiftToolsVersion
        )
    }
}
