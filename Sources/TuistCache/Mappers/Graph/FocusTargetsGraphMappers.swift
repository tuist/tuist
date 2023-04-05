import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// `FocusTargetsGraphMappers` is used to filter out some targets and their dependencies and tests targets.
public final class FocusTargetsGraphMappers: GraphMapping {
    /// The targets name to be kept as non prunable with their respective dependencies and tests targets
    let includedTargets: Set<String>
    let excludedTargets: Set<String>

    public init(includedTargets: Set<String>, excludedTargets: Set<String> = []) {
        self.includedTargets = includedTargets
        self.excludedTargets = excludedTargets
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph
        let allInternalTargetsName = Set(graphTraverser.allInternalTargets().map(\.target.name))
        let userSpecifiedSourceTargets = graphTraverser.allTargets().filter { target in
            if !includedTargets.isEmpty {
                return includedTargets.contains(target.target.name)
            }
            if excludedTargets.contains(target.target.name) {
                return false
            }
            return allInternalTargetsName.contains(target.target.name)
        }
        let filteredTargets = Set(try topologicalSort(
            Array(userSpecifiedSourceTargets),
            successors: { Array(graphTraverser.directTargetDependencies(path: $0.path, name: $0.target.name)) }
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

    private func isIncluded(_ target: GraphTarget) -> Bool {
        switch (includedTargets.isEmpty, includedTargets.contains(target.target.name)) {
        case (true, _):
            break
        case let (false, isIncluded):
            return isIncluded
        }
        if excludedTargets.contains(target.target.name) {
            return false
        }
        return true
    }
}
