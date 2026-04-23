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
        requestedTargets: Set<String>
    ) -> CacheWarmTargetGraphSelection {
        guard !requestedTargets.isEmpty else {
            return .allReachable
        }

        let requestedGraphTargets = graphTraverser.allTargets().filter { requestedTargets.contains($0.target.name) }
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
