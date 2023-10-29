import Foundation
import TSCBasic
import TuistCore
import TuistGraph

/// `FocusTargetsGraphMappers` is used to filter out some targets and their dependencies and tests targets.
public final class FocusTargetsGraphMappers: GraphMapping {
    // When specified, if includedTargets is empty it will automatically include all targets in the test plan
    let testPlan: String?
    /// The targets name to be kept as non prunable with their respective dependencies and tests targets
    let includedTargets: Set<String>
    let excludedTargets: Set<String>

    public init(
        testPlan: String? = nil,
        includedTargets: Set<String>,
        excludedTargets: Set<String> = []
    ) {
        self.testPlan = testPlan
        self.includedTargets = includedTargets
        self.excludedTargets = excludedTargets
    }

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphTraverser = GraphTraverser(graph: graph)
        var graph = graph
        let userSpecifiedSourceTargets = graphTraverser.filterIncludedTargets(
            basedOn: graphTraverser.allTargets(),
            testPlan: testPlan,
            includedTargets: includedTargets,
            excludedTargets: excludedTargets,
            excludingExternalTargets: true
        )

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
}
