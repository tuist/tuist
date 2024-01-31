import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

final class FetchService {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let fileHandler: FileHandling

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader()),
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.swiftPackageManagerController = swiftPackageManagerController
        self.fileHandler = fileHandler
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
        logger.info("Resolving and fetching plugins.", metadata: .section)

        let config = try configLoader.loadConfig(path: path)
        _ = try await pluginService.loadPlugins(using: config)

        logger.info("Plugins resolved and fetched successfully.", metadata: .success)
    }

    private func fetchDependencies(path: AbsolutePath, update: Bool) throws {
        let packageManifestPath = path.appending(
            components: Constants.tuistDirectoryName,
            Constants.SwiftPackageManager.packageSwiftName
        )

        guard fileHandler.exists(packageManifestPath) else {
            return
        }

        if update {
            logger.info("Updating dependencies.", metadata: .section)

            try swiftPackageManagerController.update(at: packageManifestPath.parentDirectory, printOutput: true)
        } else {
            logger.info("Resolving and fetching dependencies.", metadata: .section)

            try swiftPackageManagerController.resolve(at: packageManifestPath.parentDirectory, printOutput: true)
        }
    }
}
