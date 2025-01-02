import FileSystem
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
    private let manifestFilesLocator: ManifestFilesLocating
    private let rootDirectoryLocator: RootDirectoryLocating

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator()
    ) {
        self.manifestLoader = manifestLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.manifestFilesLocator = manifestFilesLocator
        self.rootDirectoryLocator = rootDirectoryLocator
    }

    public func loadPackageSettings(at path: AbsolutePath, with plugins: Plugins) async throws -> TuistCore.PackageSettings {
        let path = try await manifestFilesLocator.locatePackageManifest(at: path)?.parentDirectory ?? path
        try manifestLoader.register(plugins: plugins)
        let manifest = try await manifestLoader.loadPackageSettings(at: path)
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: path)
        let generatorPaths = GeneratorPaths(
            manifestDirectory: path,
            rootDirectory: rootDirectory
        )

        return try TuistCore.PackageSettings.from(
            manifest: manifest,
            generatorPaths: generatorPaths
        )
    }
}
