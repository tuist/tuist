import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLinting
import TuistLoader
import TuistSupport

enum LintCodeServiceError: FatalError, Equatable {
    /// Thrown when neither a workspace or a project is found in the given path.
    case manifestNotFound(AbsolutePath)
    /// Thrown when target with given name does not exist.
    case targetNotFound(String)
    /// Throws when no lintable files found for target with given name.
    case lintableFilesForTargetNotFound(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .manifestNotFound, .targetNotFound, .lintableFilesForTargetNotFound:
            return .abort
        }
    }

    /// Description
    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find Project.swift nor Workspace.swift at \(path.pathString)"
        case let .targetNotFound(name):
            return "Target with name '\(name)' not found in the project."
        case let .lintableFilesForTargetNotFound(name):
            return "No lintable files for target with name '\(name)'."
        }
    }
}

final class LintCodeService {
    private let rootDirectoryLocator: RootDirectoryLocating
    private let codeLinter: CodeLinting
    private let graphLoader: GraphLoading
    private let manifestLoading: ManifestLoading

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
         codeLinter: CodeLinting = CodeLinter(),
         manifestLoading: ManifestLoading = ManifestLoader(),
         graphLoader: GraphLoading = GraphLoader(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                   manifestLinter: AnyManifestLinter())))
    {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.codeLinter = codeLinter
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
    }

    func run(path: String?, targetName: String?) throws {
        // Determine destination path
        let path = self.path(path)

        // Load graph
        let graph = try loadDependencyGraph(at: path)

        // Get sources
        let sources = try getSources(targetName: targetName, graph: graph)

        // Lint code
        logger.notice("Running code linting")
        try codeLinter.lint(sources: sources, path: path)
    }

    // MARK: - Destination path

    private func path(_ path: String?) -> AbsolutePath {
        guard let path = path else { return FileHandler.shared.currentPath }

        return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
    }

    // MARK: - Load dependency graph

    private func loadDependencyGraph(at path: AbsolutePath) throws -> Graph {
        let manifests = manifestLoading.manifests(at: path)

        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            let graph = try graphLoader.loadWorkspace(path: path)
            return graph
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            let (graph, _) = try graphLoader.loadProject(path: path)
            return graph
        } else {
            throw LintCodeServiceError.manifestNotFound(path)
        }
    }

    // MARK: - Get sources to lint

    private func getSources(targetName: String?, graph: Graph) throws -> [AbsolutePath] {
        if let targetName = targetName {
            return try getTargetSources(targetName: targetName, graph: graph)
        } else {
            return graph.targets
                .flatMap(\.value)
                .flatMap(\.target.sources)
                .map(\.path)
        }
    }

    private func getTargetSources(targetName: String, graph: Graph) throws -> [AbsolutePath] {
        guard let target = graph.targets.flatMap(\.value)
            .map(\.target)
            .first(where: { $0.name == targetName })
        else {
            throw LintCodeServiceError.targetNotFound(targetName)
        }

        let sources = target.sources.map(\.path)

        if sources.isEmpty {
            throw LintCodeServiceError.lintableFilesForTargetNotFound(targetName)
        }
        return sources
    }
}
