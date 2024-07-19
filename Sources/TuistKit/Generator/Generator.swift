import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistDependencies
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport
import XcodeGraph

@Mockable
public protocol Generating {
    @discardableResult
    func load(path: AbsolutePath) async throws -> Graph
    func generate(path: AbsolutePath) async throws -> AbsolutePath
    func generateWithGraph(path: AbsolutePath) async throws -> (AbsolutePath, Graph)
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
            fileHandler: FileHandler.shared
        )
        self.manifestGraphLoader = manifestGraphLoader
    }

    public func generate(path: AbsolutePath) async throws -> AbsolutePath {
        let (generatedPath, _) = try await generateWithGraph(path: path)
        return generatedPath
    }

    public func generateWithGraph(path: AbsolutePath) async throws -> (AbsolutePath, Graph) {
        let (graph, sideEffects) = try await load(path: path)

        // Load
        let graphTraverser = GraphTraverser(graph: graph)

        // Lint
        try await lint(graphTraverser: graphTraverser)

        // Generate
        let workspaceDescriptor = try generator.generateWorkspace(graphTraverser: graphTraverser)

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

        return (workspaceDescriptor.xcworkspacePath, graph)
    }

    public func load(path: AbsolutePath) async throws -> Graph {
        try await load(path: path).0
    }

    func load(path: AbsolutePath) async throws -> (Graph, [SideEffectDescriptor]) {
        logger.notice("Loading and constructing the graph", metadata: .section)
        logger.notice("It might take a while if the cache is empty")

        let (graph, sideEffectDescriptors, issues) = try await manifestGraphLoader.load(path: path)

        lintingIssues.append(contentsOf: issues)
        return (graph, sideEffectDescriptors)
    }

    private func lint(graphTraverser: GraphTraversing) async throws {
        let config = try await configLoader.loadConfig(path: graphTraverser.path)

        let environmentIssues = try environmentLinter.lint(config: config)
        try environmentIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: environmentIssues)

        let graphIssues = graphLinter.lint(graphTraverser: graphTraverser, config: config)
        try graphIssues.printAndThrowErrorsIfNeeded()
        lintingIssues.append(contentsOf: graphIssues)
    }

    private func postGenerationActions(graphTraverser: GraphTraversing, workspaceName: String) async throws {
        let config = try await configLoader.loadConfig(path: graphTraverser.path)

        try await swiftPackageManagerInteractor.install(
            graphTraverser: graphTraverser,
            workspaceName: workspaceName,
            config: config
        )
    }

    private func printAndFlushPendingLintWarnings() {
        // Print out warnings, if any
        lintingIssues.printWarningsIfNeeded()
        lintingIssues.removeAll()
    }
}
