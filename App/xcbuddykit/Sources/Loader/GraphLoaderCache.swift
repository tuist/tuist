import Basic
import Foundation

/// Cache used during the graph loading. It keeps a reference to the nodes that are part of the dependency graph.
protocol GraphLoaderCaching: AnyObject {
    /// Projects
    var projects: [AbsolutePath: Project] { get }

    /// Target nodes.
    var targetNodes: [AbsolutePath: [String: TargetNode]] { get }

    /// Precompiled nodes.
    var precompiledNodes: [AbsolutePath: PrecompiledNode] { get }

    /// Returns a project from the cache.
    ///
    /// - Parameter path: path to the folder where the Project.swift file is.
    /// - Returns: project if it exists in the cache.
    func project(_ path: AbsolutePath) -> Project?

    /// Adds a project to the cache.
    ///
    /// - Parameter project: project to be added to the cache.
    func add(project: Project)

    /// Returns a configuration from the cache.
    ///
    /// - Parameter path: path to the folder where the Config.swift is.
    /// - Returns: configuration if it exists in the cache.
    func config(_ path: AbsolutePath) -> Config?

    /// Adds a configuration to the cache.
    ///
    /// - Parameter config: configuration to be added.
    func add(config: Config)

    /// Adds a precompiled node to the cache.
    ///
    /// - Parameter precompiledNode: precompiled node to be added.
    func add(precompiledNode: PrecompiledNode)

    /// Returns a precompiled node from the cache.
    ///
    /// - Parameter path: path to the the precompiled node (e.g. /path/to/xcbuddykit.framework)
    /// - Returns: a precompiled node if it exists.
    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode?

    /// Adds a target node to the cache.
    ///
    /// - Parameter targetNode: target node to be added.
    func add(targetNode: TargetNode)

    /// Gets a target node from the cache.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the Project.swift where the target is defined.
    ///   - name: target name.
    /// - Returns: a target node from the cache if it exsits
    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode?
}

/// Graph loader cache.
class GraphLoaderCache: GraphLoaderCaching {
    /// Projects.
    var projects: [AbsolutePath: Project] = [:]

    /// Configs.
    var configs: [AbsolutePath: Config] = [:]

    /// Precompiled nodes.
    var precompiledNodes: [AbsolutePath: PrecompiledNode] = [:]

    /// Target nodes.
    var targetNodes: [AbsolutePath: [String: TargetNode]] = [:]

    /// Returns a project from the cache.
    ///
    /// - Parameter path: path to the folder where the Project.swift file is.
    /// - Returns: project if it exists in the cache.
    func project(_ path: AbsolutePath) -> Project? {
        return projects[path]
    }

    /// Adds a project to the cache.
    ///
    /// - Parameter project: project to be added to the cache.
    func add(project: Project) {
        projects[project.path] = project
    }

    /// Returns a configuration from the cache.
    ///
    /// - Parameter path: path to the folder where the Config.swift is.
    /// - Returns: configuration if it exists in the cache.
    func config(_ path: AbsolutePath) -> Config? {
        return configs[path]
    }

    /// Adds a configuration to the cache.
    ///
    /// - Parameter config: configuration to be added.
    func add(config: Config) {
        configs[config.path] = config
    }

    /// Adds a precompiled node to the cache.
    ///
    /// - Parameter precompiledNode: precompiled node to be added.
    func add(precompiledNode: PrecompiledNode) {
        precompiledNodes[precompiledNode.path] = precompiledNode
    }

    /// Returns a precompiled node from the cache.
    ///
    /// - Parameter path: path to the the precompiled node (e.g. /path/to/xcbuddykit.framework)
    /// - Returns: a precompiled node if it exists.
    func precompiledNode(_ path: AbsolutePath) -> PrecompiledNode? {
        return precompiledNodes[path]
    }

    /// Adds a target node to the cache.
    ///
    /// - Parameter targetNode: target node to be added.
    func add(targetNode: TargetNode) {
        var projectTargets: [String: TargetNode]! = targetNodes[targetNode.path]
        if projectTargets == nil { projectTargets = [:] }
        projectTargets[targetNode.target.name] = targetNode
        targetNodes[targetNode.path] = projectTargets
    }

    /// Gets a target node from the cache.
    ///
    /// - Parameters:
    ///   - path: path to the folder that contains the Project.swift where the target is defined.
    ///   - name: target name.
    /// - Returns: a target node from the cache if it exsits
    func targetNode(_ path: AbsolutePath, name: String) -> TargetNode? {
        return targetNodes[path]?[name]
    }
}
