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
    private let manifestLoader: ManifestLoading
    private let dependenciesController: DependenciesControlling
    private let dependenciesModelLoader: DependenciesModelLoading
    private let converter: ManifestModelConverting
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileHandler: FileHandling
    
    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(manifestLoader: CachedManifestLoader()),
        manifestLoader: ManifestLoading = ManifestLoader(),
        dependenciesController: DependenciesControlling = DependenciesController(),
        dependenciesModelLoader: DependenciesModelLoading = DependenciesModelLoader(),
        converter: ManifestModelConverting = ManifestModelConverter(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.dependenciesController = dependenciesController
        self.dependenciesModelLoader = dependenciesModelLoader
        self.converter = converter
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileHandler = fileHandler
    }
    
    func run(
        path: String?,
        update: Bool
    ) async throws {
        let path = try self.locateDependencies(at: path)
        try await fetchDependencies(path: path, update: update, with: fetchPlugins(path: path))
    }
    
    // MARK: - Helpers
    
    public func locateDependencies(at path: String?) throws -> AbsolutePath {
        // Convert to AbsolutePath
        let path = try self.path(path)
        
        // If the Dependencies.swift file exists in the root Tuist directory, we load it from there
        if let rootDirectoryPath = rootDirectoryLocator.locate(from: path) {
            if fileHandler.exists(
                rootDirectoryPath.appending(components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(path))
            ) {
                return rootDirectoryPath
            }
        }
        
        // Else, we try to traverse up the directories to find it
        if let traversedPath = fileHandler.locateDirectoryTraversingParents(from: path, path: Constants.tuistDirectoryName) {
            if fileHandler.exists(
                traversedPath.appending(components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(path))
            ) {
                return traversedPath
            }
        }
        
        // Otherwise return the original path
        return path
    }
    
    private func path(_ path: String?) throws -> AbsolutePath {
        
        if let path {
            return try AbsolutePath(validating: path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }
    
    private var currentPath: AbsolutePath {
        fileHandler.currentPath
    }
    
    private func fetchPlugins(path: AbsolutePath) async throws -> TuistGraph.Plugins {
        logger.info("Resolving and fetching plugins.", metadata: .section)
        
        let config = try configLoader.loadConfig(path: path)
        let plugins = try await pluginService.loadPlugins(using: config)
        
        logger.info("Plugins resolved and fetched successfully.", metadata: .success)
        
        return plugins
    }
    
    private func fetchDependencies(path: AbsolutePath, update: Bool, with plugins: TuistGraph.Plugins) throws {
        try manifestLoader.validateHasProjectOrWorkspaceManifest(at: path)
        
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
        
        let dependencies = try dependenciesModelLoader.loadDependencies(at: path, with: plugins)
        
        let config = try configLoader.loadConfig(path: path)
        let swiftVersion = config.swiftVersion
        
        let dependenciesManifest: TuistCore.DependenciesGraph
        
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
