import Foundation
import TSCBasic
import TuistPlugin
import TuistSupport
import TuistLoader
import TuistDependencies

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

    func run(path: String?, fetchCategories: [FetchCategory]) throws {
        let path = self.path(path)
        try fetchCategories.forEach {
            switch $0 {
            case .plugins:
                try fetchPlugins(path: path)
            case .dependencies:
                try fetchDependencies(path: path)
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
    
    private func fetchPlugins(path: AbsolutePath) throws {
        logger.info("Resolving and fetching plugins.", metadata: .section)
        
        let config = try configLoader.loadConfig(path: path)
        try pluginService.fetchRemotePlugins(using: config)
        
        logger.info("Plugins resolved and fetched successfully.", metadata: .success)
    }
    
    private func fetchDependencies(path: AbsolutePath) throws {
        guard FileHandler.shared.exists(
            path.appending(components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(path))
        ) else {
            return
        }
        
        logger.info("Resolving and fetching dependencies.", metadata: .section)

        let dependencies = try dependenciesModelLoader.loadDependencies(at: path)

        let config = try configLoader.loadConfig(path: path)
        let swiftVersion = config.swiftVersion

        let dependenciesManifest = try dependenciesController.fetch(
            at: path,
            dependencies: dependencies,
            swiftVersion: swiftVersion
        )

        let dependenciesGraph = try converter.convert(manifest: dependenciesManifest, path: path)

        try dependenciesController.save(
            dependenciesGraph: dependenciesGraph,
            to: path
        )

        logger.info("Dependencies resolved and fetched successfully.", metadata: .success)
    }
}

