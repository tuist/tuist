import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
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
    /// Graph linter
    private let graphLinter: GraphLinting
    private let environmentLinter: EnvironmentLinting
    private let manifestLoading: ManifestLoading
    private let graphLoader: ValueGraphLoading
    private let modelLoader: GeneratorModelLoading
    private let configLoader: ConfigLoading

    convenience init() {
        let manifestLoader = ManifestLoader()
        let modelLoader = GeneratorModelLoader(
            manifestLoader: manifestLoader,
            manifestLinter: AnyManifestLinter()
        )
        let graphLoader = ValueGraphLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        let graphLinter = GraphLinter()
        let environmentLinter = EnvironmentLinter()
        self.init(
            graphLinter: graphLinter,
            environmentLinter: environmentLinter,
            manifestLoading: manifestLoader,
            graphLoader: graphLoader,
            modelLoader: modelLoader,
            configLoader: configLoader
        )
    }

    init(
        graphLinter: GraphLinting,
        environmentLinter: EnvironmentLinting,
        manifestLoading: ManifestLoading,
        graphLoader: ValueGraphLoading,
        modelLoader: GeneratorModelLoading,
        configLoader: ConfigLoading
    ) {
        self.graphLinter = graphLinter
        self.environmentLinter = environmentLinter
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
        self.modelLoader = modelLoader
        self.configLoader = configLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)

        // Load graph
        let manifests = manifestLoading.manifests(at: path)
        let graph: ValueGraph

        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            let workspace = try modelLoader.loadWorkspace(at: path)
            let projects = try workspace.projects.map(modelLoader.loadProject)
            graph = try graphLoader.loadWorkspace(workspace: workspace, projects: projects)
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            let project = try modelLoader.loadProject(at: path)
            (_, graph) = try graphLoader.loadProject(at: path, projects: [project])
        } else {
            throw LintProjectServiceError.manifestNotFound(path)
        }
        let graphTraverser = ValueGraphTraverser(graph: graph)

        logger.notice("Running linters")
        let config = try configLoader.loadConfig(path: path)

        var issues: [LintingIssue] = []
        logger.notice("Linting the environment")
        issues.append(contentsOf: try environmentLinter.lint(config: config))
        logger.notice("Linting the loaded dependency graph")
        issues.append(contentsOf: graphLinter.lint(graphTraverser: graphTraverser))

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
