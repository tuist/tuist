import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// `FilterTargetsDependenciesTreeGraphMapper` is used to filter out some targets and their dependencies
public final class FilterTargetsDependenciesTreeGraphMapper: GraphMapping {
    /// The targets name to be kept as non prunable with their respective dependencies
    private let includedTargets: Set<String>?

    public init(includedTargets: Set<String>?) {
        self.includedTargets = includedTargets
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph
        let filteredTargets: Set<GraphTarget>
        if let includedTargets = includedTargets {
            filteredTargets = Set(try topologicalSort(
                Array(graphTraverser.allTargets().filter { includedTargets.contains($0.target.name) }),
                successors: {
                    Array(graphTraverser.directTargetDependencies(path: $0.path, name: $0.target.name))
                }
            ))
        } else {
            filteredTargets = []
        }

        graphTraverser.allTargets().forEach { graphTarget in
            if !filteredTargets.contains(graphTarget) {
                var target = graphTarget.target
                target.prune = true
                graph.targets[graphTarget.path]?[target.name] = target
            }
        }
        return (graph, [])
    }
}
