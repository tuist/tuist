import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistPlugin
import TuistSigning
import TuistSupport

protocol Generating {
    @discardableResult
    func load(path: AbsolutePath) throws -> ValueGraph
    func loadProject(path: AbsolutePath) throws -> (Project, ValueGraph, [SideEffectDescriptor]) // swiftlint:disable:this large_tuple
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, ValueGraph)
    func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, ValueGraph)
}

class Generator: Generating {
    private let recursiveManifestLoader: RecursiveManifestLoading
    private let converter: ManifestModelConverting
    private let manifestLinter: ManifestLinting = ManifestLinter()
    private let graphLinter: GraphLinting = GraphLinter()
    private let environmentLinter: EnvironmentLinting = EnvironmentLinter()
    private let generator: DescriptorGenerating = DescriptorGenerator()
    private let writer: XcodeProjWriting = XcodeProjWriter()
    private let cocoapodsInteractor: CocoaPodsInteracting = CocoaPodsInteractor()
    private let swiftPackageManagerInteractor: SwiftPackageManagerInteracting = SwiftPackageManagerInteractor()
    private let signingInteractor: SigningInteracting = SigningInteractor()
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let graphMapperProvider: GraphMapperProviding
    private let projectMapperProvider: ProjectMapperProviding
    private let workspaceMapperProvider: WorkspaceMapperProviding
    private let manifestLoader: ManifestLoading
    private let pluginsService: PluginServicing
    private let configLoader: ConfigLoading

    convenience init(contentHasher: ContentHashing) {
        self.init(
            projectMapperProvider: ProjectMapperProvider(contentHasher: contentHasher),
            graphMapperProvider: GraphMapperProvider(),
            workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }

    init(
        projectMapperProvider: ProjectMapperProviding,
        graphMapperProvider: GraphMapperProviding,
        workspaceMapperProvider: WorkspaceMapperProviding,
        manifestLoaderFactory: ManifestLoaderFactory
    ) {
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        recursiveManifestLoader = RecursiveManifestLoader(manifestLoader: manifestLoader)
        converter = ManifestModelConverter(
            manifestLoader: manifestLoader
        )
        sideEffectDescriptorExecutor = SideEffectDescriptorExecutor()
        self.graphMapperProvider = graphMapperProvider
        self.projectMapperProvider = projectMapperProvider
        self.workspaceMapperProvider = workspaceMapperProvider
        self.manifestLoader = manifestLoader
        pluginsService = PluginService(manifestLoader: manifestLoader)
        configLoader = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: RootDirectoryLocator(),
            fileHandler: FileHandler.shared
        )
    }

    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath {
        let (generatedPath, _) = try generateWithGraph(path: path, projectOnly: projectOnly)
        return generatedPath
    }

    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, ValueGraph) {
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

    func load(path: AbsolutePath) throws -> ValueGraph {
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
    func loadProject(path: AbsolutePath) throws -> (Project, ValueGraph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)

        // Load all manifests
        let manifests = try recursiveManifestLoader.loadProject(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let models = try convert(manifests: manifests)

        // Apply any registered model mappers
        let projectMapper = projectMapperProvider.mapper(
            config: config,
            plugins: plugins
        )
        let updatedModels = try models.map(projectMapper.map)
        let updatedProjects = updatedModels.map(\.0)
        let modelMapperSideEffects = updatedModels.flatMap(\.1)

        // Load Graph
        let graphLoader = ValueGraphLoader()
        let (project, graph) = try graphLoader.loadProject(
            at: path,
            projects: updatedProjects
        )

        // Apply graph mappers
        let (updatedGraph, graphMapperSideEffects) = try graphMapperProvider
            .mapper(config: config)
            .map(graph: graph)

        return (project, updatedGraph, modelMapperSideEffects + graphMapperSideEffects)
    }

    private func generateProject(path: AbsolutePath) throws -> (AbsolutePath, ValueGraph) {
        // Load
        let (project, graph, sideEffects) = try loadProject(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)

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

    private func generateWorkspace(path: AbsolutePath) throws -> (AbsolutePath, ValueGraph) {
        // Load
        let (graph, sideEffects) = try loadWorkspace(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)

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

    internal func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, ValueGraph) {
        // Load
        let (_, graph, sideEffects) = try loadProjectWorkspace(path: path)
        let graphTraverser = ValueGraphTraverser(graph: graph)

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
    }

    private func postGenerationActions(graphTraverser: GraphTraversing, workspaceName: String) throws {
        let config = try configLoader.loadConfig(path: graphTraverser.path)

        try signingInteractor.install(graphTraverser: graphTraverser)
        try swiftPackageManagerInteractor.install(graphTraverser: graphTraverser, workspaceName: workspaceName, config: config)
        try cocoapodsInteractor.install(graphTraverser: graphTraverser)
    }

    // swiftlint:disable:next large_tuple
    private func loadProjectWorkspace(path: AbsolutePath) throws -> (Project, ValueGraph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)

        // Load all manifests
        let manifests = try recursiveManifestLoader.loadProject(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let projects = try convert(manifests: manifests)

        let workspaceName = manifests.projects[path]?.name ?? "Workspace"
        let workspace = Workspace(
            path: path,
            xcWorkspacePath: path.appending(component: "\(workspaceName).xcworkspace"),
            name: workspaceName,
            projects: []
        )
        let models = (workspace: workspace, projects: projects)

        // Apply any registered model mappers
        let workspaceMapper = workspaceMapperProvider.mapper(
            config: config,
            plugins: plugins
        )
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let graphLoader = ValueGraphLoader()
        var (project, graph) = try graphLoader.loadProject(
            at: path,
            projects: updatedModels.projects
        )
        graph.workspace = updatedModels.workspace

        // Apply graph mappers
        var (updatedGraph, graphMapperSideEffects) = try graphMapperProvider
            .mapper(config: config)
            .map(graph: graph)

        var updatedWorkspace = updatedGraph.workspace
        updatedWorkspace = updatedWorkspace.merging(projects: updatedGraph.projects.map(\.key))
        updatedGraph.workspace = updatedWorkspace

        return (
            project,
            updatedGraph,
            modelMapperSideEffects + graphMapperSideEffects
        )
    }

    private func loadWorkspace(path: AbsolutePath) throws -> (ValueGraph, [SideEffectDescriptor]) {
        // Load config
        let config = try configLoader.loadConfig(path: path)

        // Load Plugins
        let plugins = try pluginsService.loadPlugins(using: config)
        manifestLoader.register(plugins: plugins)

        // Load all manifests
        let manifests = try recursiveManifestLoader.loadWorkspace(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Convert to models
        let models = try convert(manifests: manifests)

        // Apply model mappers
        let workspaceMapper = workspaceMapperProvider.mapper(
            config: config,
            plugins: plugins
        )
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let graphLoader = ValueGraphLoader()
        let graph = try graphLoader.loadWorkspace(
            workspace: updatedModels.workspace,
            projects: updatedModels.projects
        )

        // Apply graph mappers
        let (mappedGraph, graphMapperSideEffects) = try graphMapperProvider
            .mapper(config: config)
            .map(graph: graph)

        return (mappedGraph, modelMapperSideEffects + graphMapperSideEffects)
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
