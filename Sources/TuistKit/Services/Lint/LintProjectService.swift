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
    private let graphLinter: GraphLinting
    private let environmentLinter: EnvironmentLinting
    private let configLoader: ConfigLoading
    private let simpleGraphLoader: SimpleGraphLoading

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let configLoader = ConfigLoader(manifestLoader: manifestLoader)
        let graphLinter = GraphLinter()
        let environmentLinter = EnvironmentLinter()
        let simpleGraphLoader = SimpleGraphLoader(manifestLoader: manifestLoader)
        self.init(
            graphLinter: graphLinter,
            environmentLinter: environmentLinter,
            configLoader: configLoader,
            simpleGraphLoader: simpleGraphLoader
        )
    }

    init(
        graphLinter: GraphLinting,
        environmentLinter: EnvironmentLinting,
        configLoader: ConfigLoading,
        simpleGraphLoader: SimpleGraphLoading
    ) {
        self.graphLinter = graphLinter
        self.environmentLinter = environmentLinter
        self.configLoader = configLoader
        self.simpleGraphLoader = simpleGraphLoader
    }

    func run(path: String?) throws {
        let path = self.path(path)

        logger.notice("Loading the dependency graph at \(path)")
        let graph = try simpleGraphLoader.loadGraph(at: path)
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
