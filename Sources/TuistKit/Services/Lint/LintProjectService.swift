import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
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
    private let graphLoader: GraphLoading

    init(graphLinter: GraphLinting = GraphLinter(),
         environmentLinter: EnvironmentLinting = EnvironmentLinter(),
         manifestLoading: ManifestLoading = ManifestLoader(),
         graphLoader: GraphLoading = GraphLoader(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                   manifestLinter: AnyManifestLinter())))
    {
        self.graphLinter = graphLinter
        self.environmentLinter = environmentLinter
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)

        // Load graph
        let manifests = manifestLoading.manifests(at: path)
        var graph: Graph!

        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            (graph, _) = try graphLoader.loadWorkspace(path: path)
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            (graph, _) = try graphLoader.loadProject(path: path)
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
