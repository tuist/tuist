import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSupport

/// A utility for loading a graph for a given Manifest path on disk
///
/// - Any configured plugins are loaded
/// - All referenced manifests are loaded
/// - All manifests are concurrently transformed to models
/// - A graph is loaded from the models
///
/// - Note: This is a simplified implementation that loads a graph without applying any mappers or running any linters
protocol ManifestGraphLoading {
    /// Loads a Workspace or Project Graph at a given path based on manifest availability
    /// - Note: This will search for a Workspace manifest first, then fallback to searching for a Project manifest
    func loadGraph(at path: AbsolutePath) throws -> ValueGraph
}

final class ManifestGraphLoader: ManifestGraphLoading {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let recursiveManifestLoader: RecursiveManifestLoader
    private let converter: ManifestModelConverting
    private let graphLoader: ValueGraphLoading
    private let pluginsService: PluginServicing

    convenience init(manifestLoader: ManifestLoading) {
        self.init(
            configLoader: ConfigLoader(manifestLoader: manifestLoader),
            manifestLoader: manifestLoader,
            recursiveManifestLoader: RecursiveManifestLoader(manifestLoader: manifestLoader),
            converter: ManifestModelConverter(
                manifestLoader: manifestLoader
            ),
            graphLoader: ValueGraphLoader(),
            pluginsService: PluginService(manifestLoader: manifestLoader)
        )
    }

    init(
        configLoader: ConfigLoading,
        manifestLoader: ManifestLoading,
        recursiveManifestLoader: RecursiveManifestLoader,
        converter: ManifestModelConverting,
        graphLoader: ValueGraphLoading,
        pluginsService: PluginServicing
    ) {
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.recursiveManifestLoader = recursiveManifestLoader
        self.converter = converter
        self.graphLoader = graphLoader
        self.pluginsService = pluginsService
    }

    func loadGraph(at path: AbsolutePath) throws -> ValueGraph {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try loadWorkspaceGraph(at: path)
        } else if manifests.contains(.project) {
            return try loadProjectGraph(at: path).1
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    func loadPlugins(at path: AbsolutePath) throws {
        let config = try configLoader.loadConfig(path: path)
        let plugins = try pluginsService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)
    }

    // MARK: - Private

    private func loadProjectGraph(at path: AbsolutePath) throws -> (Project, ValueGraph) {
        try loadPlugins(at: path)
        let manifests = try recursiveManifestLoader.loadProject(at: path)
        let models = try convert(manifests: manifests)
        return try graphLoader.loadProject(at: path, projects: models)
    }

    private func loadWorkspaceGraph(at path: AbsolutePath) throws -> ValueGraph {
        try loadPlugins(at: path)
        let manifests = try recursiveManifestLoader.loadWorkspace(at: path)
        let models = try convert(manifests: manifests)
        return try graphLoader.loadWorkspace(workspace: models.workspace, projects: models.projects)
    }

    private func convert(manifests: LoadedProjects,
                         context: ExecutionContext = .concurrent) throws -> [TuistGraph.Project]
    {
        let tuples = manifests.projects.map { (path: $0.key, manifest: $0.value) }
        return try tuples.map(context: context) {
            try converter.convert(manifest: $0.manifest, path: $0.path)
        }
    }

    private func convert(manifests: LoadedWorkspace,
                         context: ExecutionContext = .concurrent) throws -> (workspace: Workspace, projects: [TuistGraph.Project])
    {
        let workspace = try converter.convert(manifest: manifests.workspace, path: manifests.path)
        let tuples = manifests.projects.map { (path: $0.key, manifest: $0.value) }
        let projects = try tuples.map(context: context) {
            try converter.convert(manifest: $0.manifest, path: $0.path)
        }
        return (workspace, projects)
    }
}
