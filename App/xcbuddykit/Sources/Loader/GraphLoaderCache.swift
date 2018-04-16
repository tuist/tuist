import Foundation
import PathKit

protocol GraphLoaderCaching {
    func project(_ path: Path) -> Project?
    func add(project: Project)
    func config(_ path: Path) -> Config?
    func add(config: Config)
    func add(node: GraphNode)
    func node(_ path: Path) -> GraphNode?
}

class GraphLoaderCache: GraphLoaderCaching {
    var projects: [Path: Project] = [:]
    var configs: [Path: Config] = [:]
    var nodes: [Path: GraphNode] = [:]

    func project(_ path: Path) -> Project? {
        return projects[path]
    }

    func add(project: Project) {
        projects[project.path] = project
    }

    func config(_ path: Path) -> Config? {
        return configs[path]
    }

    func add(config: Config) {
        configs[config.path] = config
    }

    func add(node: GraphNode) {
        nodes[node.path] = node
    }

    func node(_ path: Path) -> GraphNode? {
        return nodes[path]
    }
}
