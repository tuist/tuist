import Foundation
import TSCBasic

public protocol ValueGraphTraversing {
    init(graph: ValueGraph)

    /// Given a project directory and target name, it returns all its direct target dependencies.
    /// - Parameters:
    ///   - path: Path to the directory that contains the project.
    ///   - name: Target name.
    func directTargetDependencies(path: AbsolutePath, name: String) -> [Target]
}

public class ValueGraphTraverser: ValueGraphTraversing {
    private let graph: ValueGraph

    public required init(graph: ValueGraph) {
        self.graph = graph
    }

    public func directTargetDependencies(path: AbsolutePath, name: String) -> [Target] {
        guard let dependencies = graph.dependencies[.target(name: name, path: path)] else { return [] }
        return dependencies.flatMap { (dependency) -> [Target] in
            guard case let ValueGraphDependency.target(dependencyName, dependencyPath) = dependency else { return [] }
            guard let projectDependencies = graph.targets[dependencyPath], let dependencyTarget = projectDependencies[dependencyName] else { return []
            }
            return [dependencyTarget]
        }
    }
}
