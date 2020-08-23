import Foundation
import TSCBasic
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

enum LintCodeServiceError: FatalError, Equatable {
    /// Thrown when neither a workspace or a project is found in the given path.
    case manifestNotFound(AbsolutePath)
    /// Thrown when neither a workspace or a project is found in the given path.
    case targetNotFound(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .manifestNotFound, .targetNotFound:
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
        }
    }
}

final class LintCodeService {
    private let binaryLocator: BinaryLocating
    private let graphLoader: GraphLoading
    private let manifestLoading: ManifestLoading
    private let rootDirectoryLocator: RootDirectoryLocating

    init(binaryLocator: BinaryLocating = BinaryLocator(),
         rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
         manifestLoading: ManifestLoading = ManifestLoader(),
         graphLoader: GraphLoading = GraphLoader(modelLoader: GeneratorModelLoader(manifestLoader: ManifestLoader(),
                                                                                   manifestLinter: AnyManifestLinter())))
    {
        self.binaryLocator = binaryLocator
        self.rootDirectoryLocator = rootDirectoryLocator
        self.manifestLoading = manifestLoading
        self.graphLoader = graphLoader
    }

    func run(path: String?, targetName: String?) throws {
        // Determine destination path
        let path = self.path(path)

        // Load graph
        let graph = try loadDependencyGraph(at: path)

        // Get sources
        let sources: [AbsolutePath] = try getSources(targetName: targetName, graph: graph)

        // Lint code
        let swiftLintPath = try binaryLocator.swiftLintPath()
        
        #warning("Implement: lint code (`sources`) using binary under `swiftLintPath`")
    }
}

// MARK: - Destination path

private extension LintCodeService {
    func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}

// MARK: - Load dependency graph

private extension LintCodeService {
    func loadDependencyGraph(at path: AbsolutePath) throws -> Graph {
        let manifests = manifestLoading.manifests(at: path)
        
        logger.notice("Loading the dependency graph")
        if manifests.contains(.workspace) {
            logger.notice("Loading workspace at \(path.pathString)")
            let (graph, _) = try graphLoader.loadWorkspace(path: path)
            return graph
        } else if manifests.contains(.project) {
            logger.notice("Loading project at \(path.pathString)")
            let (graph, _) = try graphLoader.loadProject(path: path)
            return graph
        } else {
            throw LintCodeServiceError.manifestNotFound(path)
        }
    }
}

// MARK: - Get sources to lint

private extension LintCodeService {
    func getSources(targetName: String?, graph: Graph) throws -> [AbsolutePath] {
        if let targetName = targetName {
            return try getTargetSources(targetName: targetName, graph: graph)
        } else {
            return getAllSources(graph: graph)
        }
    }
    
    func getAllSources(graph: Graph) -> [AbsolutePath] {
        return graph.targets.flatMap { $0.value }.map(\.target).flatMap { $0.sources }.map { $0.path }
    }
    
    func getTargetSources(targetName: String, graph: Graph) throws -> [AbsolutePath] {
        guard let target = graph.targets.flatMap({ $0.value }).map(\.target).first(where: { $0.name == targetName }) else {
            throw LintCodeServiceError.targetNotFound(targetName)
        }
        
        return target.sources.map { $0.path }
    }
}

// MARK: - Get SwiftLint's config path

private extension LintCodeService {
    #warning("Thorw error if config can not be found?")
    func swiftlintConfigPath(path: AbsolutePath) -> AbsolutePath? {
        guard let rootPath = rootDirectoryLocator.locate(from: path) else { return nil }
        return ["yml", "yaml"].compactMap { (fileExtension) -> AbsolutePath? in
            let swiftlintPath = rootPath.appending(RelativePath("\(Constants.tuistDirectoryName)/swiftlint.\(fileExtension)"))
            return (FileHandler.shared.exists(swiftlintPath)) ? swiftlintPath : nil
        }.first
    }
}
