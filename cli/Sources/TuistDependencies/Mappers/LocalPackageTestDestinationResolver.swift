import TuistCore
import XcodeGraph

struct LocalPackageTestDestinationResolver {
    func resolve(
        graphTraverser: GraphTraversing,
        productionDestinations: [GraphTarget: Set<Destination>],
        graphBeforeTestFocus: Graph? = nil
    ) -> [GraphTarget: Set<Destination>] {
        let referenceTraverser: GraphTraversing
        let inferredProductionDestinations: [GraphTarget: Set<Destination>]
        if let graphBeforeTestFocus {
            referenceTraverser = GraphTraverser(graph: graphBeforeTestFocus)
            inferredProductionDestinations = referenceTraverser.externalTargetSupportedDestinations()
        } else {
            referenceTraverser = graphTraverser
            inferredProductionDestinations = productionDestinations
        }
        var result: [GraphTarget: Set<Destination>] = [:]
        for test in referenceTraverser.allExternalTargets()
            where test.target.metadata.tags.contains(TargetTags.localSwiftPackageTest)
        {
            guard let retainedTest = graphTraverser.target(path: test.path, name: test.target.name) else { continue }
            if let destinations = inferredProductionDestinations[test] {
                result[retainedTest] = destinations.intersection(retainedTest.target.destinations)
                continue
            }
            let destinations = test.target.dependencies.compactMap { dependency -> Set<Destination>? in
                let dependencyTarget: GraphTarget?
                let condition: PlatformCondition?
                switch dependency {
                case let .target(name, _, dependencyCondition):
                    dependencyTarget = referenceTraverser.target(path: test.path, name: name)
                    condition = dependencyCondition
                case let .project(name, path, _, dependencyCondition):
                    dependencyTarget = referenceTraverser.target(path: path, name: name)
                    condition = dependencyCondition
                default:
                    return nil
                }
                guard let dependencyTarget, dependencyTarget.target.isLinkable(),
                      let inheritedDestinations = inferredProductionDestinations[dependencyTarget]
                else { return nil }
                return inheritedDestinations.intersection(retainedTest.target.destinations).filter { destination in
                    condition?.platformFilters.contains(destination.platformFilter) ?? true
                }
            }
            // Absence of an inferred destination is different from an unchanged, broad declaration.
            // Only tests connected to the production traversal may extend its dependency graph.
            if let first = destinations.first {
                result[retainedTest] = destinations.dropFirst().reduce(first) { $0.union($1) }
            }
        }
        return result
    }
}
