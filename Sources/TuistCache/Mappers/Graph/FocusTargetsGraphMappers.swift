import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// `FocusTargetsGraphMappers` is used to filter out some targets and their dependencies and tests targets.
public final class FocusTargetsGraphMappers: GraphMapping {
    /// The targets name to be kept as non prunable with their respective dependencies and tests targets
    let includedTargets: Set<String>

    public init(includedTargets: Set<String>) {
        self.includedTargets = includedTargets
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph
        let includedTargets = includedTargets
            .isEmpty ? Set(
                graphTraverser.allInternalTargets()
                    .union(graphTraverser.allExternalTestsTargets())
                    .map(\.target.name)
            ) : includedTargets
        let userSpecifiedSourceTargets = graphTraverser.allTargets().filter { includedTargets.contains($0.target.name) }
        let filteredTargets = Set(try topologicalSort(
            Array(userSpecifiedSourceTargets),
            successors: { graphTarget in
                print(graphTarget.target.name)
                return Array(graphTraverser.directTargetDependencies(path: graphTarget.path, name: graphTarget.target.name))
            }
        ))

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
