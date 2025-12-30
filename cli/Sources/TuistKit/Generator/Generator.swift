import FileSystem
import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistRootDirectoryLocator
import TuistSupport
import XcodeGraph

@Mockable
public protocol Generating {
    @discardableResult
    func load(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws -> Graph
    func generate(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws
        -> (AbsolutePath, Graph, MapperEnvironment)
}

public class Generator: Generating {
    private let graphLinter: GraphLinting = GraphLinter()
    private let environmentLinter: EnvironmentLinting = EnvironmentLinter()
    private let generator: DescriptorGenerating = DescriptorGenerator()
    private let writer: XcodeProjWriting = XcodeProjWriter()
    private let swiftPackageManagerInteractor: TuistGenerator.SwiftPackageManagerInteracting = TuistGenerator
        .SwiftPackageManagerInteractor()
    private let sideEffectDescriptorExecutor: SideEffectDescriptorExecuting
    private let configLoader: ConfigLoading
    private let manifestGraphLoader: ManifestGraphLoading
    private var lintingIssues: [LintingIssue] = []

    public init(
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        sideEffectDescriptorExecutor = SideEffectDescriptorExecutor()
        configLoader = ConfigLoader(
            manifestLoader: manifestLoader,
            rootDirectoryLocator: RootDirectoryLocator(),
            fileSystem: FileSystem()
        )
        self.manifestGraphLoader = manifestGraphLoader
    }

    public func generate(
        path: AbsolutePath,
        options: TuistGeneratedProjectOptions.GenerationOptions?
    ) async throws -> AbsolutePath {
        let (generatedPath, _, _) = try await generateWithGraph(path: path, options: options)
        return generatedPath
    }

    public func generateWithGraph(
        path: AbsolutePath,
        options: TuistGeneratedProjectOptions.GenerationOptions?
    ) async throws -> (AbsolutePath, Graph, MapperEnvironment) {
        let (graph, sideEffects, environment) = try await load(path: path, options: options)

        // Load
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        // When mutating the graph to use cache, we currently end up double linking some frameworks.
        // To workaround those false positive warnings, we lint the graph before we replace source modules with xcframeworks
        // And assume the changes in the mapper are correct.
        try await lint(graphTraverser: GraphTraverser(graph: environment.initialGraphWithSources ?? graph))

        // Generate
        let workspaceDescriptor = try await generator.generateWorkspace(graphTraverser: graphTraverser)

        // Write
        try await writer.write(workspace: workspaceDescriptor)

        // Mapper side effects
        try await sideEffectDescriptorExecutor.execute(sideEffects: sideEffects)

        // Post Generate Actions
        try await postGenerationActions(
            graphTraverser: graphTraverser,
            workspaceName: workspaceDescriptor.xcworkspacePath.basename
        )

        printAndFlushPendingLintWarnings()

        return (workspaceDescriptor.xcworkspacePath, graph, environment)
    }

    public func load(path: AbsolutePath, options: TuistGeneratedProjectOptions.GenerationOptions?) async throws -> Graph {
        try await load(path: path, options: options).0
    }

    func load(
        path: AbsolutePath,
        options: TuistGeneratedProjectOptions
            .GenerationOptions?
    ) async throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        Logger.current.notice("Loading and constructing the graph", metadata: .section)
        Logger.current.notice("It might take a while if the cache is empty")

        let (graph, sideEffectDescriptors, environment, issues) = try await manifestGraphLoader.load(
            path: path,
            disableSandbox: options?.disableSandbox ?? true
        )

        lintingIssues.append(contentsOf: issues)
        return (graph, sideEffectDescriptors, environment)
    }

    private func lint(graphTraverser: GraphTraversing) async throws {
        guard let configGeneratedProjectOptions = (try await configLoader.loadConfig(path: graphTraverser.path)).project
            .generatedProject
        else {
            return
        }

        let environmentIssues = try await environmentLinter.lint(configGeneratedProjectOptions: configGeneratedProjectOptions)
        try environmentIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: environmentIssues)

        let graphIssues = try await graphLinter.lint(
            graphTraverser: graphTraverser,
            configGeneratedProjectOptions: configGeneratedProjectOptions
        )
        try graphIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: graphIssues)
    }

    private func postGenerationActions(graphTraverser: GraphTraversing, workspaceName: String) async throws {
        guard let configGeneratedProjectOptions = (try await configLoader.loadConfig(path: graphTraverser.path)).project
            .generatedProject
        else {
            return
        }

        try await swiftPackageManagerInteractor.install(
            graphTraverser: graphTraverser,
            workspaceName: workspaceName,
            configGeneratedProjectOptions: configGeneratedProjectOptions
        )
    }

    private func printAndFlushPendingLintWarnings() {
        // Print out warnings, if any
        lintingIssues.printWarningsIfNeeded()
        lintingIssues.removeAll()
    }
}
