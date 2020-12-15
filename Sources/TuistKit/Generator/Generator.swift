import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSigning
import TuistSupport

protocol Generating {
    @discardableResult
    func load(path: AbsolutePath) throws -> Graph
    func loadProject(path: AbsolutePath) throws -> (Project, Graph, [SideEffectDescriptor])
    func generate(path: AbsolutePath, projectOnly: Bool) throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath, projectOnly: Bool) throws -> (AbsolutePath, Graph)
    func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph)
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
    private let modelLoader: GeneratorModelLoading
    private let graphLoader: GraphLoading
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let graphMapperProvider: GraphMapperProviding
    private let projectMapperProvider: ProjectMapperProviding
    private let workspaceMapperProvider: WorkspaceMapperProviding
    private let manifestLoader: ManifestLoading

    convenience init(contentHasher: ContentHashing) {
        self.init(projectMapperProvider: ProjectMapperProvider(contentHasher: contentHasher),
                  graphMapperProvider: GraphMapperProvider(),
                  workspaceMapperProvider: WorkspaceMapperProvider(contentHasher: contentHasher),
                  manifestLoaderFactory: ManifestLoaderFactory())
    }

    init(projectMapperProvider: ProjectMapperProviding,
         graphMapperProvider: GraphMapperProviding,
         workspaceMapperProvider: WorkspaceMapperProviding,
         manifestLoaderFactory: ManifestLoaderFactory)
    {
        let manifestLoader = manifestLoaderFactory.createManifestLoader()
        recursiveManifestLoader = RecursiveManifestLoader(manifestLoader: manifestLoader)
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                               manifestLinter: manifestLinter)
        converter = modelLoader
        graphLoader = GraphLoader(modelLoader: modelLoader)
        sideEffectDescriptorExecutor = SideEffectDescriptorExecutor()
        self.modelLoader = modelLoader
        self.graphMapperProvider = graphMapperProvider
        self.projectMapperProvider = projectMapperProvider
        self.workspaceMapperProvider = workspaceMapperProvider
        self.manifestLoader = manifestLoader
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
    func loadProject(path: AbsolutePath) throws -> (Project, Graph, [SideEffectDescriptor]) {
        // Load all manifests
        let manifests = try recursiveManifestLoader.loadProject(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Load config
        let config = try graphLoader.loadConfig(path: path)

        // Convert to models
        let models = try convert(manifests: manifests)

        // Apply any registered model mappers
        let projectMapper = projectMapperProvider.mapper(config: config)
        let updatedModels = try models.map(projectMapper.map)
        let updatedProjects = updatedModels.map(\.0)
        let modelMapperSideEffects = updatedModels.flatMap(\.1)

        // Load Graph
        let cachedModelLoader = CachedModelLoader(projects: updatedProjects)
        let cachedGraphLoader = GraphLoader(modelLoader: cachedModelLoader)
        let (graph, project) = try cachedGraphLoader.loadProject(path: path)

        // Apply graph mappers
        let (updatedGraph, graphMapperSideEffects) = try graphMapperProvider.mapper(config: config).map(graph: graph)

        return (project, updatedGraph, modelMapperSideEffects + graphMapperSideEffects)
    }

    private func generateProject(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (project, graph, sideEffects) = try loadProject(path: path)

        // Lint
        try lint(graph: graph)

        // Generate
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)
        let projectDescriptor = try generator.generateProject(project: project, graphTraverser: graphTraverser)

        // Write
        try writer.write(project: projectDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(for: graph, workspaceName: projectDescriptor.xcodeprojPath.basename)

        return (projectDescriptor.xcodeprojPath, graph)
    }

    private func generateWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (graph, sideEffects) = try loadWorkspace(path: path)

        // Lint
        try lint(graph: graph)

        // Generate
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(for: graph, workspaceName: workspaceDescriptor.xcworkspacePath.basename)

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    internal func generateProjectWorkspace(path: AbsolutePath) throws -> (AbsolutePath, Graph) {
        // Load
        let (_, graph, sideEffects) = try loadProjectWorkspace(path: path)

        // Lint
        try lint(graph: graph)

        // Generate
        let valueGraph = ValueGraph(graph: graph)
        let graphTraverser = ValueGraphTraverser(graph: valueGraph)
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try postGenerationActions(for: graph, workspaceName: workspaceDescriptor.xcworkspacePath.basename)

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    private func lint(graph: Graph) throws {
        let config = try graphLoader.loadConfig(path: graph.entryPath)

        try environmentLinter.lint(config: config).printAndThrowIfNeeded()
        try graphLinter.lint(graph: graph).printAndThrowIfNeeded()
    }

    private func postGenerationActions(for graph: Graph, workspaceName: String) throws {
        try signingInteractor.install(graph: graph)
        try swiftPackageManagerInteractor.install(graph: graph, workspaceName: workspaceName)
        try cocoapodsInteractor.install(graph: graph)
    }

    // swiftlint:disable:next large_tuple
    private func loadProjectWorkspace(path: AbsolutePath) throws -> (Project, Graph, [SideEffectDescriptor]) {
        // Load all manifests
        let manifests = try recursiveManifestLoader.loadProject(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Load config
        let config = try graphLoader.loadConfig(path: path)

        // Convert to models
        let projects = try convert(manifests: manifests)

        let workspaceName = manifests.projects[path]?.name ?? "Workspace"
        let workspace = Workspace(path: path, name: workspaceName, projects: [])
        let models = (workspace: workspace, projects: projects)

        // Apply any registered model mappers
        let workspaceMapper = workspaceMapperProvider.mapper(config: config)
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let cachedModelLoader = CachedModelLoader(projects: updatedModels.projects)
        let cachedGraphLoader = GraphLoader(modelLoader: cachedModelLoader)
        let (graph, project) = try cachedGraphLoader.loadProject(path: path)

        // Apply graph mappers
        let (updatedGraph, graphMapperSideEffects) = try graphMapperProvider.mapper(config: config).map(graph: graph)
        let updatedWorkspace = updatedModels
            .workspace
            .merging(projects: updatedGraph.projects.map(\.path))

        return (
            project,
            updatedGraph.with(workspace: updatedWorkspace),
            modelMapperSideEffects + graphMapperSideEffects
        )
    }

    // swiftlint:disable:next large_tuple
    private func loadWorkspace(path: AbsolutePath) throws -> (Graph, [SideEffectDescriptor]) {
        // Load all manifests
        let manifests = try recursiveManifestLoader.loadWorkspace(at: path)

        // Lint Manifests
        try manifests.projects.flatMap {
            manifestLinter.lint(project: $0.value)
        }.printAndThrowIfNeeded()

        // Load config
        let config = try graphLoader.loadConfig(path: path)

        // Convert to models
        let models = try convert(manifests: manifests)

        // Apply model mappers
        let workspaceMapper = workspaceMapperProvider.mapper(config: config)
        let (updatedModels, modelMapperSideEffects) = try workspaceMapper.map(
            workspace: .init(workspace: models.workspace, projects: models.projects)
        )

        // Load Graph
        let cachedModelLoader = CachedModelLoader(workspace: [updatedModels.workspace], projects: updatedModels.projects)
        let cachedGraphLoader = GraphLoader(modelLoader: cachedModelLoader)
        let graph = try cachedGraphLoader.loadWorkspace(path: path)

        // Apply graph mappers
        let (mappedGraph, graphMapperSideEffects) = try graphMapperProvider.mapper(config: config).map(graph: graph)

        return (mappedGraph, modelMapperSideEffects + graphMapperSideEffects)
    }

    private func convert(manifests: LoadedProjects,
                         context: ExecutionContext = .concurrent) throws -> [TuistCore.Project]
    {
        let tuples = manifests.projects.map { (path: $0.key, manifest: $0.value) }
        return try tuples.map(context: context) {
            try converter.convert(manifest: $0.manifest, path: $0.path)
        }
    }

    private func convert(manifests: LoadedWorkspace,
                         context: ExecutionContext = .concurrent) throws -> (workspace: Workspace, projects: [TuistCore.Project])
    {
        let workspace = try converter.convert(manifest: manifests.workspace, path: manifests.path)
        let tuples = manifests.projects.map { (path: $0.key, manifest: $0.value) }
        let projects = try tuples.map(context: context) {
            try converter.convert(manifest: $0.manifest, path: $0.path)
        }
        return (workspace, projects)
    }
}
