import Foundation
import RxBlocking
import TSCBasic
import TuistCore
import TuistGenerator
import TuistGraph
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
    private let graphLoader: ValueGraphLoading
    private let modelLoader: GeneratorModelLoading
    private let manifestLoading: ManifestLoading

    init(rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
         codeLinter: CodeLinting = CodeLinter(),
         manifestLoading: ManifestLoading = ManifestLoader(),
         modelLoader: GeneratorModelLoading = GeneratorModelLoader(
             manifestLoader: ManifestLoader(),
             manifestLinter: AnyManifestLinter()
         ),
         graphLoader: ValueGraphLoading = ValueGraphLoader())
    {
        self.rootDirectoryLocator = rootDirectoryLocator
        self.codeLinter = codeLinter
        self.manifestLoading = manifestLoading
        self.modelLoader = modelLoader
        self.graphLoader = graphLoader
    }

    func run(path: String?, targetName: String?, strict: Bool) throws {
        // Determine destination path
        let path = self.path(path)

        // Load graph
        let graph = try loadDependencyGraph(at: path)

        // Get sources
        let graphTraverser = ValueGraphTraverser(graph: graph)
        let sources = try getSources(targetName: targetName, graphTraverser: graphTraverser)

        // Lint code
        logger.notice("Running code linting")
        try codeLinter.lint(sources: sources, path: path, strict: strict)
    }

    // MARK: - Destination path

    private func path(_ path: String?) -> AbsolutePath {
        guard let path = path else { return FileHandler.shared.currentPath }

        return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
    }

    // MARK: - Load dependency graph

    private func loadDependencyGraph(at path: AbsolutePath) throws -> ValueGraph {
        let manifests = manifestLoading.manifests(at: path)

        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            let workspace = try modelLoader.loadWorkspace(at: path)
            let projects = try workspace.projects.map(modelLoader.loadProject)
            let graph = try graphLoader.loadWorkspace(workspace: workspace, projects: projects)
            return graph
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            let project = try modelLoader.loadProject(at: path)
            let (_, graph) = try graphLoader.loadProject(at: path, projects: [project])
            return graph
        } else {
            throw LintCodeServiceError.manifestNotFound(path)
        }
    }

    // MARK: - Get sources to lint

    private func getSources(targetName: String?, graphTraverser: GraphTraversing) throws -> [AbsolutePath] {
        if let targetName = targetName {
            return try getTargetSources(targetName: targetName, graphTraverser: graphTraverser)
        } else {
            return graphTraverser.allTargets()
                .flatMap(\.target.sources)
                .map(\.path)
        }
    }

    private func getTargetSources(targetName: String, graphTraverser: GraphTraversing) throws -> [AbsolutePath] {
        guard let target = graphTraverser.allTargets()
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
