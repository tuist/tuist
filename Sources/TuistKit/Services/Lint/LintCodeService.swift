import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum LintCodeServiceError: FatalError, Equatable {
    /// Thrown when neither a workspace or a project is found in the given path.
    case targetNotFound(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .targetNotFound:
            return .abort
        }
    }

    /// Description
    var description: String {
        switch self {
        case let .targetNotFound(name):
            return "Target with name '\(name)' not found in the project."
        }
    }
}

final class LintCodeService {
    private let graphLoader: GraphLoading
    private let manifestLoading: ManifestLoading
    private let codeLinter: CodeLinting

    init(codeLinter: CodeLinting = CodeLinter(),
         rootDirectoryLocator _: RootDirectoryLocating = RootDirectoryLocator(),
         manifestLoading: ManifestLoading = ManifestLoader(),
         graphLoader: GraphLoading = GraphLoader(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                   manifestLinter: AnyManifestLinter())))
    {
        self.codeLinter = codeLinter
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
    }

    func run(path: String?, targetName: String?) throws {
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

        // Get sources
        let sources: [AbsolutePath]
        if let targetName = targetName {
            if let target = graph.targets.flatMap({ $0.value }).map(\.target).first(where: { $0.name == targetName }) {
                sources = target.sources.map { $0.path }
            } else {
                throw LintCodeServiceError.targetNotFound(targetName)
            }
        } else {
            sources = graph.targets.flatMap { $0.value }.map(\.target).flatMap { $0.sources }.map { $0.path }
        }

        try codeLinter.lint(sources: sources, path: path)
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
