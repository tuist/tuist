import Foundation
import TSCBasic
import TuistCore
import TuistDependencies
import TuistLoader
import TuistPlugin
import TuistSupport

final class FetchService {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading
    private let converter: ManifestModelConverting

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader()),
        dependenciesController: DependenciesControlling = DependenciesController(),
        dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader(),
        converter: ManifestModelConverting = ManifestModelConverter()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
        self.converter = converter
    }

    func run(
        path: String?,
        fetchCategories: [FetchCategory],
        update: Bool
    ) async throws {
        let path = self.path(path)
        for fetchCategory in fetchCategories {
            switch fetchCategory {
            case .plugins:
                try await fetchPlugins(path: path)
            case .dependencies:
                try fetchDependencies(path: path, update: update)
            }
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }

    private func fetchPlugins(path: AbsolutePath) async throws {
        logger.info("Resolving and fetching plugins.", metadata: .section)

        let config = try configLoader.loadConfig(path: path)
        try await pluginService.fetchRemotePlugins(using: config)

        logger.info("Plugins resolved and fetched successfully.", metadata: .success)
    }

    private func fetchDependencies(path: AbsolutePath, update: Bool) throws {
        guard FileHandler.shared.exists(
            path.appending(components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(path))
        ) else {
            return
        }

        if update {
            logger.info("Updating dependencies.", metadata: .section)
        } else {
            logger.info("Resolving and fetching dependencies.", metadata: .section)
        }

        let dependencies = try dependenciesModelLoader.loadDependencies(at: path)

        let config = try configLoader.loadConfig(path: path)
        let swiftVersion = config.swiftVersion

        let dependenciesManifest: DependenciesGraph
        if update {
            dependenciesManifest = try dependenciesController.update(
                at: path,
                dependencies: dependencies,
                swiftVersion: swiftVersion
            )
        } else {
            dependenciesManifest = try dependenciesController.fetch(
                at: path,
                dependencies: dependencies,
                swiftVersion: swiftVersion
            )
        }

        let dependenciesGraph = try converter.convert(manifest: dependenciesManifest, path: path)

        try dependenciesController.save(
            dependenciesGraph: dependenciesGraph,
            to: path
        )

        if update {
            logger.info("Dependencies updated successfully.", metadata: .success)
        } else {
            logger.info("Dependencies resolved and fetched successfully.", metadata: .success)
        }
    }
}
