import Basic
import Foundation

class GraphLoader {
    func load(path: AbsolutePath) throws -> GraphController {
        let context = GraphLoaderContext()
        if context.fileHandler.exists(path.appending(component: Constants.Manifest.project)) {
            return try loadProject(path: path, context: context)
        } else if context.fileHandler.exists(path.appending(component: Constants.Manifest.workspace)) {
            return try loadWorkspace(path: path, context: context)
        } else {
            throw GraphLoadingError.manifestNotFound(path)
        }
    }

    fileprivate func loadProject(path: AbsolutePath, context: GraphLoaderContext) throws -> GraphController {
        let project = try Project.read(path: path, context: context)
        let entryNodes: [GraphNode] = try project.targets.map({ $0.name }).map { targetName in
            return try TargetNode.read(name: targetName, path: path, context: context)
        }
        return GraphController(cache: context.cache, entryNodes: entryNodes)
    }

    fileprivate func loadWorkspace(path: AbsolutePath, context: GraphLoaderContext) throws -> GraphController {
        let workspace = try Workspace(path: path, context: context)
        let projects = try workspace.projects.map { (projectPath) -> (AbsolutePath, Project) in
            return try (projectPath, Project.read(path: projectPath, context: context))
        }
        let entryNodes = try projects.flatMap { (project) -> [TargetNode] in
            return try project.1.targets.map({ $0.name }).map { targetName in
                try TargetNode.read(name: targetName, path: project.0, context: context)
            }
        }
        return GraphController(cache: context.cache, entryNodes: entryNodes)
    }
}
