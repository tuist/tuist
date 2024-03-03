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
public protocol ManifestGraphLoading {
    /// Loads a Workspace or Project Graph at a given path based on manifest availability
    /// - Note: This will search for a Workspace manifest first, then fallback to searching for a Project manifest
    func load(path: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor], [LintingIssue])
    // swiftlint:disable:previous large_tuple
}

public final class ManifestGraphLoader: ManifestGraphLoading {
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let recursiveManifestLoader: RecursiveManifestLoading
    private let converter: ManifestModelConverting
    private let graphLoader: GraphLoading
    private let pluginsService: PluginServicing
    private let swiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading
    private let graphLoaderLinter: CircularDependencyLinting
    private let manifestLinter: ManifestLinting
    private let workspaceMapper: WorkspaceMapping
    private let graphMapper: GraphMapping
    private let packageSettingsLoader: PackageSettingsLoading
    private let manifestFilesLocator: ManifestFilesLocating

    public convenience init(
        manifestLoader: ManifestLoading,
        workspaceMapper: WorkspaceMapping,
        graphMapper: GraphMapping
    ) {
        self.init(
            configLoader: ConfigLoader(manifestLoader: manifestLoader),
            manifestLoader: manifestLoader,
            recursiveManifestLoader: RecursiveManifestLoader(manifestLoader: manifestLoader),
            converter: ManifestModelConverter(
                manifestLoader: manifestLoader
            ),
            graphLoader: GraphLoader(),
            pluginsService: PluginService(manifestLoader: manifestLoader),
            swiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoader(manifestLoader: manifestLoader),
            graphLoaderLinter: CircularDependencyLinter(),
            manifestLinter: ManifestLinter(),
            workspaceMapper: workspaceMapper,
            graphMapper: graphMapper,
            packageSettingsLoader: PackageSettingsLoader(manifestLoader: manifestLoader),
            manifestFilesLocator: ManifestFilesLocator()
        )
    }

    init(
        configLoader: ConfigLoading,
        manifestLoader: ManifestLoading,
        recursiveManifestLoader: RecursiveManifestLoader,
        converter: ManifestModelConverting,
        graphLoader: GraphLoading,
        pluginsService: PluginServicing,
        swiftPackageManagerGraphLoader: SwiftPackageManagerGraphLoading,
        graphLoaderLinter: CircularDependencyLinting,
        manifestLinter: ManifestLinting,
        workspaceMapper: WorkspaceMapping,
        graphMapper: GraphMapping,
        packageSettingsLoader: PackageSettingsLoading,
        manifestFilesLocator: ManifestFilesLocating
    ) {
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.recursiveManifestLoader = recursiveManifestLoader
        self.converter = converter
        self.graphLoader = graphLoader
        self.pluginsService = pluginsService
        self.swiftPackageManagerGraphLoader = swiftPackageManagerGraphLoader
        self.graphLoaderLinter = graphLoaderLinter
        self.manifestLinter = manifestLinter
        self.workspaceMapper = workspaceMapper
        self.graphMapper = graphMapper
        self.packageSettingsLoader = packageSettingsLoader
        self.manifestFilesLocator = manifestFilesLocator
    }

    // swiftlint:disable:next function_body_length large_tuple
    public func load(path: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor], [LintingIssue]) {
        try manifestLoader.validateHasRootManifest(at: path)

        // Load Plugins
        let plugins = try await loadPlugins(at: path)

        // Load DependenciesGraph

        let dependenciesGraph: TuistGraph.DependenciesGraph
        let packageSettings: TuistGraph.PackageSettings?
        if let packagePath = manifestFilesLocator.locatePackageManifest(at: path) {
            let loadedPackageSettings = try packageSettingsLoader.loadPackageSettings(
                at: packagePath.parentDirectory,
                with: plugins
            )
            dependenciesGraph = try converter.convert(
                manifest: try swiftPackageManagerGraphLoader.load(
                    packagePath: packagePath,
                    packageSettings: loadedPackageSettings
                ),
                path: path
            )
            packageSettings = loadedPackageSettings
        } else {
            packageSettings = nil
            dependenciesGraph = .none
        }

        let allManifests = try recursiveManifestLoader.loadWorkspace(
            at: path,
            packageSettings: packageSettings
        )
        let (workspaceModels, manifestProjects) = (
            try converter.convert(manifest: allManifests.workspace, path: allManifests.path),
            allManifests.projects
        )

        // Lint Manifests
        let lintingIssues = manifestProjects.flatMap { manifestLinter.lint(project: $0.value) }
        try lintingIssues.printAndThrowErrorsIfNeeded()

        // Convert to models
        let projectsModels = try convert(
            projects: manifestProjects,
            plugins: plugins,
            externalDependencies: dependenciesGraph.externalDependencies
        ) +
            dependenciesGraph.externalProjects.values

        // Check circular dependencies
        try graphLoaderLinter.lintWorkspace(workspace: workspaceModels, projects: projectsModels)

        // Apply any registered model mappers
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: workspaceModels, projects: projectsModels)
        )

        // Load graph
        let graphLoader = GraphLoader()
        let graph = try graphLoader.loadWorkspace(
            workspace: updatedModels.workspace,
            projects: updatedModels.projects
        )

        // Apply graph mappers
        let (mappedGraph, graphMapperSideEffects) = try await graphMapper.map(graph: graph)

        return (
            mappedGraph,
            modelMapperSideEffects + graphMapperSideEffects,
            lintingIssues
        )
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
                externalDependencies: externalDependencies,
                isExternal: false
            )
        }
    }

    @discardableResult
    func loadPlugins(at path: AbsolutePath) async throws -> Plugins {
        let config = try configLoader.loadConfig(path: path)
        let plugins = try await pluginsService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)
        return plugins
    }
}
