import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
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
    func loadGraph(at path: AbsolutePath) throws -> Graph
}

final class ManifestGraphLoader: ManifestGraphLoading {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let recursiveManifestLoader: RecursiveManifestLoader
    private let converter: ManifestModelConverting
    private let graphLoader: GraphLoading
    private let pluginsService: PluginServicing
    private let dependenciesGraphController: DependenciesGraphControlling
    private let graphLoaderLinter: CircularDependencyLinting

    convenience init(manifestLoader: ManifestLoading) {
        self.init(
            configLoader: ConfigLoader(manifestLoader: manifestLoader),
            manifestLoader: manifestLoader,
            recursiveManifestLoader: RecursiveManifestLoader(manifestLoader: manifestLoader),
            converter: ManifestModelConverter(
                manifestLoader: manifestLoader
            ),
            graphLoader: GraphLoader(),
            pluginsService: PluginService(manifestLoader: manifestLoader),
            dependenciesGraphController: DependenciesGraphController(),
            graphLoaderLinter: CircularDependencyLinter()
        )
    }

    init(
        configLoader: ConfigLoading,
        manifestLoader: ManifestLoading,
        recursiveManifestLoader: RecursiveManifestLoader,
        converter: ManifestModelConverting,
        graphLoader: GraphLoading,
        pluginsService: PluginServicing,
        dependenciesGraphController: DependenciesGraphControlling,
        graphLoaderLinter: CircularDependencyLinting
    ) {
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.recursiveManifestLoader = recursiveManifestLoader
        self.converter = converter
        self.graphLoader = graphLoader
        self.pluginsService = pluginsService
        self.dependenciesGraphController = dependenciesGraphController
        self.graphLoaderLinter = graphLoaderLinter
    }

    func loadGraph(at path: AbsolutePath) throws -> Graph {
        let manifests = manifestLoader.manifests(at: path)
        if manifests.contains(.workspace) {
            return try loadWorkspaceGraph(at: path)
        } else if manifests.contains(.project) {
            return try loadProjectGraph(at: path).1
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    @discardableResult
    func loadPlugins(at path: AbsolutePath) throws -> Plugins {
        let config = try configLoader.loadConfig(path: path)
        let plugins = try pluginsService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)
        return plugins
    }

    // MARK: - Private

    private func loadProjectGraph(at path: AbsolutePath) throws -> (TuistGraph.Project, Graph) {
        let plugins = try loadPlugins(at: path)
        let dependenciesGraph = try dependenciesGraphController.load(at: path)
        let manifests = try recursiveManifestLoader.loadProject(at: path)
        let models = try convert(
            projects: manifests.projects,
            plugins: plugins,
            externalDependencies: dependenciesGraph.externalDependencies
        ) +
            dependenciesGraph.externalProjects.values
        try graphLoaderLinter.lintProject(at: path, projects: models)
        return try graphLoader.loadProject(at: path, projects: models)
    }

    private func loadWorkspaceGraph(at path: AbsolutePath) throws -> Graph {
        let plugins = try loadPlugins(at: path)
        let dependenciesGraph = try dependenciesGraphController.load(at: path)
        let manifests = try recursiveManifestLoader.loadWorkspace(at: path)
        let workspace = try converter.convert(manifest: manifests.workspace, path: manifests.path)
        let models = try convert(
            projects: manifests.projects,
            plugins: plugins,
            externalDependencies: dependenciesGraph.externalDependencies
        ) +
            dependenciesGraph.externalProjects.values
        try graphLoaderLinter.lintWorkspace(workspace: workspace, projects: models)
        return try graphLoader.loadWorkspace(workspace: workspace, projects: models)
    }

    private func convert(
        projects: [AbsolutePath: ProjectDescription.Project],
        plugins: Plugins,
        externalDependencies: [String: [TuistGraph.TargetDependency]],
        context: ExecutionContext = .concurrent
    ) throws -> [TuistGraph.Project] {
        let tuples = projects.map { (path: $0.key, manifest: $0.value) }
        return try tuples.map(context: context) {
            try converter.convert(
                manifest: $0.manifest,
                path: $0.path,
                plugins: plugins,
                externalDependencies: externalDependencies
            )
        }
    }
}
