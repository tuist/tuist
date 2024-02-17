import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class InstallService {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let fileHandler: FileHandling
    private let manifestFilesLocator: ManifestFilesLocating

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader()),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        fileHandler: FileHandling = FileHandler.shared,
        manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.fileHandler = fileHandler
        self.manifestFilesLocator = manifestFilesLocator
    }

    func run(
        path: String?,
        update: Bool
    ) async throws {
        let path = try self.path(path)

        try await fetchPlugins(path: path)
        try fetchDependencies(path: path, update: update)
    }

    // MARK: - Helpers

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: fileHandler.currentPath)
        } else {
            return fileHandler.currentPath
        }
    }

    private func fetchPlugins(path: AbsolutePath) async throws {
        logger.notice("Resolving and fetching plugins.", metadata: .section)

        let config = try configLoader.loadConfig(path: path)
        _ = try await pluginService.loadPlugins(using: config)

        logger.notice("Plugins resolved and fetched successfully.", metadata: .success)
    }

    private func fetchDependencies(path: AbsolutePath, update: Bool) throws {
        guard
            let packageManifestPath = manifestFilesLocator.locatePackageManifest(at: path)
        else {
            return
        }

        if update {
            logger.notice("Updating dependencies.", metadata: .section)

            try swiftPackageManagerController.update(at: packageManifestPath.parentDirectory, printOutput: true)
        } else {
            logger.notice("Resolving and fetching dependencies.", metadata: .section)

            try swiftPackageManagerController.resolve(at: packageManifestPath.parentDirectory, printOutput: true)
        }
    }
}
