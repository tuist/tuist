import Basic
import Foundation

protocol GraphLoaderCaching: AnyObject {
    var projects: [AbsolutePath: Project] { get }
    var targetNodes: [AbsolutePath: [String: TargetNode]] { get }
    var precompiledNodes: [AbsolutePath: PrecompiledNode] { get }
    func project(_ path: AbsolutePath) -> Project?
    func add(project: Project)
    func add(precompiledNode: PrecompiledNode)
    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode?
    func add(targetNode: TargetNode)
    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode?
    func tuistConfig(_ path: AbsolutePath) -> TuistConfig?
    func add(tuistConfig: TuistConfig, path: AbsolutePath)
}

/// Graph loader cache.
class GraphLoaderCache: GraphLoaderCaching {
    // MARK: - GraphLoaderCaching

    var tuistConfigs: [AbsolutePath: TuistConfig] = [:]
    var projects: [AbsolutePath: Project] = [:]
    var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]
    var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]

    func tuistConfig(_ path: AbsolutePath) -> TuistConfig? {
        return tuistConfigs[path]
    }

    func add(tuistConfig: TuistConfig, path: AbsolutePath) {
        tuistConfigs[path] = tuistConfig
    }

    func project(_ path: AbsolutePath) -> Project? {
        return projects[path]
    }

    func add(project: Project) {
        projects[project.path] = project
    }

    func add(precompiledNode: PrecompiledNode) {
        precompiledNodes[precompiledNode.path] = precompiledNode
    }

    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        return precompiledNodes[path]
    }

    func add(targetNode: TargetNode) {
        var projectTargets: [String: TargetNode]! = targetNodes[targetNode.path]
        if projectTargets == nil { projectTargets = [:] }
        projectTargets[targetNode.target.name] = targetNode
        targetNodes[targetNode.path] = projectTargets
    }

    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodes[path]?[name]
    }
}
