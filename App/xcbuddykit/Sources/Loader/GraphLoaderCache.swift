import Basic
import Foundation

protocol GraphLoaderCaching {
    func project(_ path: AbsolutePath) -> Project?
    func add(project: Project)
    func config(_ path: AbsolutePath) -> Config?
    func add(config: Config)
    func add(node: GraphNode)
    func node(_ path: AbsolutePath) -> GraphNode?
}

class GraphLoaderCache: GraphLoaderCaching {
    var projects: [AbsolutePath: Project] = [:]
    var configs: [AbsolutePath: Config] = [:]
    var nodes: [AbsolutePath: GraphNode] = [:]

    func project(_ path: AbsolutePath) -> Project? {
        return projects[path]
    }

    func add(project: Project) {
        projects[project.path] = project
    }

    func config(_ path: AbsolutePath) -> Config? {
        return configs[path]
    }

    func add(config: Config) {
        configs[config.path] = config
    }

    func add(node: GraphNode) {
        nodes[node.path] = node
    }

    func node(_ path: AbsolutePath) -> GraphNode? {
        return nodes[path]
    }
}
