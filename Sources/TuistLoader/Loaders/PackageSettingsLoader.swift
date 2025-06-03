import Foundation
import Path
import ProjectDescription
import TSCUtility
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

/// Entity responsible for providing `PackageSettings`.
public protocol PackageSettingsLoading {
    /// Load the Dependencies model at the specified path.
    /// - Parameters:
    ///   - path: The absolute path for the `PackageSettings` to load.
    ///   - plugins: The plugins for the `PackageSettings` to load.
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    /// - Returns: The `PackageSettings` loaded from the specified path.
    func loadPackageSettings(
        at path: AbsolutePath,
        with plugins: Plugins,
        disableSandbox: Bool
    ) async throws -> TuistCore.PackageSettings
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

    public func loadPackageSettings(
        at path: AbsolutePath,
        with plugins: Plugins,
        disableSandbox: Bool
    ) async throws -> TuistCore.PackageSettings {
        let path = try await manifestFilesLocator.locatePackageManifest(at: path)?.parentDirectory ?? path
        try manifestLoader.register(plugins: plugins)
        let manifest = try await manifestLoader.loadPackageSettings(at: path, disableSandbox: disableSandbox)
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

#if DEBUG
    public class MockPackageSettingsLoader: PackageSettingsLoading {
        public init() {}

        public var invokedLoadPackageSettings = false
        public var invokedLoadPackageSettingsCount = 0
        public var invokedLoadPackageSettingsParameters: (AbsolutePath, Plugins, Bool)?
        public var invokedLoadPackageSettingsParemetersList = [(AbsolutePath, Plugins, Bool)]()
        public var loadPackageSettingsStub: ((AbsolutePath, Plugins, Bool) throws -> TuistCore.PackageSettings)?

        public func loadPackageSettings(
            at path: AbsolutePath,
            with plugins: Plugins,
            disableSandbox: Bool
        ) throws -> TuistCore.PackageSettings {
            invokedLoadPackageSettings = true
            invokedLoadPackageSettingsCount += 1
            invokedLoadPackageSettingsParameters = (path, plugins, disableSandbox)
            invokedLoadPackageSettingsParemetersList.append((path, plugins, disableSandbox))

            return try loadPackageSettingsStub?(path, plugins, disableSandbox) ?? PackageSettings.test()
        }
    }
#endif
