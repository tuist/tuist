import Foundation
import PathKit

class GraphLoader {
    private let manifestLoader: GraphManifestLoading
    private let cache: GraphLoaderCaching
    private let jsonDecoder: JSONDecoder

    init(manifestLoader: GraphManifestLoader = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         jsonDecoder: JSONDecoder = JSONDecoder()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.jsonDecoder = jsonDecoder
    }

    func load(path: Path) throws -> GraphController {
        if (path + Constants.Manifest.project).exists {
            return try loadProject(path: path)
        } else if (path + Constants.Manifest.workspace).exists {
            return try loadWorkspace(path: path)
        } else {
            throw GraphLoadingError.manifestNotFound(path)
        }
    }

    fileprivate func loadProject(path: Path) throws -> GraphController {
        let project = try Project.read(path: path, manifestLoader: manifestLoader, cache: cache)
        let entryNodes: [GraphNode] = try project.targets.map({ $0.name }).map { targetName in
            return try TargetNode.read(name: targetName, path: path, manifestLoader: manifestLoader, cache: cache)
        }
        return GraphController(cache: cache, entryNodes: entryNodes)
    }

    fileprivate func loadWorkspace(path: Path) throws -> GraphController {
        let workspace = try Workspace(path: path, manifestLoader: manifestLoader)
        let projects = try workspace.projects.map { (projectRelativePath) -> (Path, Project) in
            let projectPath = (path + projectRelativePath).absolute()
            return try (projectPath, Project.read(path: projectPath, manifestLoader: manifestLoader, cache: cache))
        }
        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            return try project.1.targets.map({ $0.name }).map { targetName in
                try TargetNode.read(name: targetName, path: project.0, manifestLoader: manifestLoader, cache: cache)
            }
        }
        return GraphController(cache: cache, entryNodes: entryNodes)
    }
}
