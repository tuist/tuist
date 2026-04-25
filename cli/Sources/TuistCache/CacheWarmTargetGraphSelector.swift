import TuistConfig
import TuistCore
import XcodeGraph

public enum CacheWarmTargetGraphSelection: Equatable {
    case allReachable
    case explicit(Set<GraphTarget>)
    case noNonTestRoots
}

public enum CacheWarmTargetGraphSelector {
    public static func selection(
        graphTraverser: GraphTraversing,
        requestedTargets: Set<TargetQuery>
    ) -> CacheWarmTargetGraphSelection {
        guard !requestedTargets.isEmpty else {
            return .allReachable
        }

        let requestedGraphTargets = graphTraverser.filterIncludedTargets(
            basedOn: graphTraverser.allTargets(),
            testPlan: nil,
            includedTargets: requestedTargets,
            excludedTargets: []
        )
        guard !requestedGraphTargets.isEmpty else {
            return .allReachable
        }

        let nonTestRoots = requestedGraphTargets.filter {
            !graphTraverser.dependsOnXCTest(path: $0.path, name: $0.target.name)
        }
        guard !nonTestRoots.isEmpty else {
            return .noNonTestRoots
        }

        let scopedTargets = graphTraverser
            .allTargetDependencies(traversingFromTargets: Array(nonTestRoots))
            .union(nonTestRoots)
        return .explicit(scopedTargets)
    }
}
