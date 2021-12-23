import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSigning
import TuistSupport

protocol Generating {
    @discardableResult
    func load(path: AbsolutePath) throws -> Graph
    func loadProject(path: AbsolutePath) throws
        -> (TuistGraph.Project, Graph, [SideEffectDescriptor]) // swiftlint:disable:this large_tuple
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graph)
    func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph)
}

class Generator: Generating {
    private let recursiveManifestLoader: RecursiveManifestLoading
    private let converter: ManifestModelConverting
    private let manifestLinter: ManifestLinting = ManifestLinter()
    private let graphLinter: GraphLinting = GraphLinter()
    private let graphLoaderLinter: CircularDependencyLinting = CircularDependencyLinter()
    private let environmentLinter: EnvironmentLinting = EnvironmentLinter()
    private let generator: DescriptorGenerating = DescriptorGenerator()
    private let writer: XcodeProjWriting = XcodeProjWriter()
    private let swiftPackageManagerInteractor: TuistGenerator.SwiftPackageManagerInteracting = TuistGenerator
        .SwiftPackageManagerInteractor()
    private let signingInteractor: SigningInteracting = SigningInteractor()
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let graphMapper: GraphMapping
    private let projectMapper: ProjectMapping
    private let workspaceMapper: WorkspaceMapping
    private let manifestLoader: ManifestLoading
    private let pluginsService: PluginServicing
    private let configLoader: ConfigLoading
    private let dependenciesGraphController: DependenciesGraphControlling

    init(
        projectMapper: ProjectMapping,
        graphMapper: GraphMapping,
        workspaceMapper: WorkspaceMapping,
        manifestLoaderFactory: ManifestLoaderFactory,
        dependenciesGraphController: DependenciesGraphControlling = DependenciesGraphController()
    ) {
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        recursiveManifestLoader = RecursiveManifestLoader(manifestLoader: manifestLoader)
        converter = ManifestModelConverter(
            manifestLoader: manifestLoader
        )
        sideEffectDescriptorExecutor = SideEffectDescriptorExecutor()
        self.graphMapper = graphMapper
        self.projectMapper = projectMapper
        self.workspaceMapper = workspaceMapper
        self.manifestLoader = manifestLoader
        pluginsService = PluginService(manifestLoader: manifestLoader)
        configLoader = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: RootDirectoryLocator(),
            fileHandler: FileHandler.shared
        )
        self.dependenciesGraphController = dependenciesGraphController
    }

    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath {
        let (generatedPath, _) = try generateWithGraph(path: path, projectOnly: projectOnly)
        return generatedPath
    }

    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graph) {
        let manifests = manifestLoader.manifests(at: path)

        if projectOnly {
            return try generateProject(path: path)
        } else if manifests.contains(.workspace) {
            return try generateWorkspace(path: path)
        } else if manifests.contains(.project) {
            return try generateProjectWorkspace(path: path)
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    func load(path: AbsolutePath) throws -> Graph {
        let manifests = manifestLoader.manifests(at: path)

        if manifests.contains(.workspace) {
            return try loadWorkspace(path: path).0
        } else if manifests.contains(.project) {
            return try loadProjectWorkspace(path: path).1
        } else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    // swiftlint:disable:next large_tuple
    func loadProject(path: AbsolutePath) throws -> (TuistGraph.Project, Graph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)

        // Load DependenciesGraph
        let dependenciesGraph = try dependenciesGraphController.load(at: path)

        // Load all manifests
        let projects = try recursiveManifestLoader.loadProject(at: path).projects

        // Lint Manifests
        try projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let models = try convert(
            projects: projects,
            plugins: plugins,
            externalDependencies: dependenciesGraph.externalDependencies
        ) +
            dependenciesGraph.externalProjects.values

        // Check circular dependencies
        try graphLoaderLinter.lintProject(at: path, projects: models)

        // Apply any registered model mappers
        let updatedModels = try models.map(projectMapper.map)
        let updatedProjects = updatedModels.map(\.0)
        let modelMapperSideEffects = updatedModels.flatMap(\.1)

        // Load Graph
        let graphLoader = GraphLoader()
        let (project, graph) = try graphLoader.loadProject(
            at: path,
            projects: updatedProjects
        )

        // Apply graph mappers
        let (updatedGraph, graphMapperSideEffects) = try graphMapper.map(graph: graph)

        return (project, updatedGraph, modelMapperSideEffects + graphMapperSideEffects)
    }

    private func generateProject(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (project, graph, sideEffects) = try loadProject(path: path)
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        try lint(graphTraverser: graphTraverser)

        // Generate
        let projectDescriptor = try generator.generateProject(project: project, graphTraverser: graphTraverser)

        // Write
        try writer.write(project: projectDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(graphTraverser: graphTraverser, workspaceName: projectDescriptor.xcodeprojPath.basename)

        return (projectDescriptor.xcodeprojPath, graph)
    }

    private func generateWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (graph, sideEffects) = try loadWorkspace(path: path)
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        try lint(graphTraverser: graphTraverser)

        // Generate
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(graphTraverser: graphTraverser, workspaceName: workspaceDescriptor.xcworkspacePath.basename)

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    internal func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (_, graph, sideEffects) = try loadProjectWorkspace(path: path)
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        try lint(graphTraverser: graphTraverser)

        // Generate
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(graphTraverser: graphTraverser, workspaceName: workspaceDescriptor.xcworkspacePath.basename)

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    private func lint(graphTraverser: GraphTraversing) throws {
        let config = try configLoader.loadConfig(path: graphTraverser.path)

        try environmentLinter.lint(config: config).printAndThrowIfNeeded()
        try graphLinter.lint(graphTraverser: graphTraverser).printAndThrowIfNeeded()
        try graphLinter.lintCodeCoverageMode(config.codeCoverageMode, graphTraverser: graphTraverser).printAndThrowIfNeeded()
    }

    private func postGenerationActions(graphTraverser: GraphTraversing, workspaceName: String) throws {
        let config = try configLoader.loadConfig(path: graphTraverser.path)

        try signingInteractor.install(graphTraverser: graphTraverser)
        try swiftPackageManagerInteractor.install(graphTraverser: graphTraverser, workspaceName: workspaceName, config: config)
    }

    // swiftlint:disable:next large_tuple
    private func loadProjectWorkspace(path: AbsolutePath) throws -> (TuistGraph.Project, Graph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)

        // Load DependenciesGraph
        let dependenciesGraph = try dependenciesGraphController.load(at: path)

        // Load all manifests
        let manifests = try recursiveManifestLoader.loadProject(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let projects = try convert(
            projects: manifests.projects,
            plugins: plugins,
            externalDependencies: dependenciesGraph.externalDependencies
        ) +
            dependenciesGraph.externalProjects.values

        let workspaceName = manifests.projects[path]?.name ?? "Workspace"
        let workspace = Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "\(workspaceName).xcworkspace"),
            name: workspaceName,
            projects: []
        )
        let models = (workspace: workspace, projects: projects)

        // Check circular dependencies
        try graphLoaderLinter.lintProject(at: path, projects: projects)

        // Apply any registered model mappers
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let graphLoader = GraphLoader()
        var (project, graph) = try graphLoader.loadProject(
            at: path,
            projects: updatedModels.projects
        )
        graph.workspace = updatedModels.workspace

        // Apply graph mappers
        var (updatedGraph, graphMapperSideEffects) = try graphMapper.map(graph: graph)

        var updatedWorkspace = updatedGraph.workspace
        updatedWorkspace = updatedWorkspace.merging(projects: updatedGraph.projects.map(\.key))
        updatedGraph.workspace = updatedWorkspace

        return (
            project,
            updatedGraph,
            modelMapperSideEffects + graphMapperSideEffects
        )
    }

    private func loadWorkspace(path: AbsolutePath) throws -> (Graph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        try manifestLoader.register(plugins: plugins)

        // Load DependenciesGraph
        let dependenciesGraph = try dependenciesGraphController.load(at: path)

        // Load all manifests
        let manifests = try recursiveManifestLoader.loadWorkspace(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let models = (
            workspace: try converter.convert(manifest: manifests.workspace, path: manifests.path),
            projects: try convert(
                projects: manifests.projects,
                plugins: plugins,
                externalDependencies: dependenciesGraph.externalDependencies
            ) +
                dependenciesGraph.externalProjects.values
        )

        // Check circular dependencies
        try graphLoaderLinter.lintWorkspace(workspace: models.workspace, projects: models.projects)

        // Apply model mappers
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let graphLoader = GraphLoader()
        let graph = try graphLoader.loadWorkspace(
            workspace: updatedModels.workspace,
            projects: updatedModels.projects
        )

        // Apply graph mappers
        let (mappedGraph, graphMapperSideEffects) = try graphMapper.map(graph: graph)

        return (mappedGraph, modelMapperSideEffects + graphMapperSideEffects)
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
