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
    /// Thrown when target with given name does not exist.
    case targetNotFound(String)
    /// Throws when no lintable files found for target with given name.
    case lintableFilesForTargetNotFound(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .targetNotFound, .lintableFilesForTargetNotFound:
            return .abort
        }
    }

    /// Description
    var description: String {
        switch self {
        case let .targetNotFound(name):
            return "Target with name '\(name)' not found in the project."
        case let .lintableFilesForTargetNotFound(name):
            return "No lintable files for target with name '\(name)'."
        }
    }
}

final class LintCodeService {
    private let codeLinter: CodeLinting
    private let manifestGraphLoader: ManifestGraphLoading

    convenience init() {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(manifestLoader: manifestLoader)
        let codeLinter = CodeLinter()
        self.init(
            codeLinter: codeLinter,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    init(
        codeLinter: CodeLinting,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        self.codeLinter = codeLinter
        self.manifestGraphLoader = manifestGraphLoader
    }

    func run(path: String?, targetName: String?, strict: Bool) throws {
        // Determine destination path
        let path = self.path(path)

        // Load graph
        logger.notice("Loading the dependency graph at \(path)")
        let graph = try manifestGraphLoader.loadGraph(at: path)

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
