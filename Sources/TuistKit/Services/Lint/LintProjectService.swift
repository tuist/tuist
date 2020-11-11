import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistPlugin
import TuistSupport

enum LintProjectServiceError: FatalError, Equatable {
    /// Thrown when neither a workspace or a project is found in the given path.
    case manifestNotFound(AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .manifestNotFound:
            return .abort
        }
    }

    /// Description
    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find Project.swift nor Workspace.swift at \(path.pathString)"
        }
    }
}

final class LintProjectService {
    private let graphLinter: GraphLinting
    private let environmentLinter: EnvironmentLinting
    private let manifestLoader: ManifestLoading
    private let modelLoader: GeneratorModelLoading
    private let graphLoader: GraphLoading
    private let pluginService: PluginServicing

    convenience init(
        graphLinter: GraphLinting = GraphLinter(),
        environmentLinter: EnvironmentLinting = EnvironmentLinter(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        manifestLinter: ManifestLinting = AnyManifestLinter()
    ) {
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader, manifestLinter: manifestLinter)
        self.init(
            graphLinter: graphLinter,
            environmentLinter: environmentLinter,
            manifestLoader: manifestLoader,
            modelLoader: modelLoader,
            graphLoader: GraphLoader(modelLoader: modelLoader)
        )
    }

    init(
        graphLinter: GraphLinting = GraphLinter(),
        environmentLinter: EnvironmentLinting = EnvironmentLinter(),
        manifestLoader: ManifestLoading = ManifestLoader(),
        modelLoader: GeneratorModelLoading = GeneratorModelLoader(manifestLoader: ManifestLoader(), manifestLinter: AnyManifestLinter()),
        pluginService: PluginServicing = PluginService(),
        graphLoader: GraphLoading
    ) {
        self.graphLinter = graphLinter
        self.environmentLinter = environmentLinter
        self.manifestLoader = manifestLoader
        self.modelLoader = modelLoader
        self.graphLoader = graphLoader
        self.pluginService = pluginService
    }

    func run(path: String?) throws {
        let path = self.path(path)

        // Load graph
        let manifests = manifestLoader.manifests(at: path)
        var graph: Graph!
        
        let plugins = try pluginService.loadPlugins(at: path)

        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            graph = try graphLoader.loadWorkspace(path: path, plugins: plugins)
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            (graph, _) = try graphLoader.loadProject(path: path, plugins: plugins)
        } else {
            throw LintProjectServiceError.manifestNotFound(path)
        }

        logger.notice("Running linters")

        let config = try graphLoader.loadConfig(path: path)

        var issues: [LintingIssue] = []
        logger.notice("Linting the environment")
        issues.append(contentsOf: try environmentLinter.lint(config: config))
        logger.notice("Linting the loaded dependency graph")
        issues.append(contentsOf: graphLinter.lint(graph: graph))

        if issues.isEmpty {
            logger.notice("No linting issues found", metadata: .success)
        } else {
            try issues.printAndThrowIfNeeded()
        }
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
