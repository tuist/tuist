import Foundation
import Path
import TSCBasic
import TuistCore
import XcodeGraph

extension GraphDependency {
    public static let allLabelNames: [String] = [
        "target", "package", "framework", "xcframework", "sdk", "bundle", "library", "macro",
    ]

    public var labelName: String {
        switch self {
        case .target: return "target"
        case .packageProduct: return "package"
        case .framework: return "framework"
        case .xcframework: return "xcframework"
        case .sdk: return "sdk"
        case .bundle: return "bundle"
        case .library: return "library"
        case .macro: return "macro"
        }
    }
}

extension XcodeGraph.Graph {
    /// Filters the project graph
    /// - Parameters:
    /// - Returns: Filtered graph targets and dependencies
    public func filter(
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        platformToFilter: Platform?,
        targetsToFilter: [String],
        sourceTargets: [String] = [],
        sinkTargets: [String] = [],
        directOnly: Bool = false,
        typeFilter: Set<String> = []
    ) -> [GraphTarget: Set<GraphDependency>] {
        let graphTraverser = GraphTraverser(graph: self)

        let allTargets: Set<GraphTarget> = skipExternalDependencies ? graphTraverser.allInternalTargets() : graphTraverser
            .allTargets()

        var filteredTargets: Set<GraphTarget> = allTargets.filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if let platformToFilter, !target.target.supports(platformToFilter) {
                return false
            }

            if !targetsToFilter.isEmpty, !targetsToFilter.contains(target.target.name) {
                return false
            }

            return true
        }

        // Apply source filter: show only what these targets depend on
        if !sourceTargets.isEmpty {
            let sources = filteredTargets.filter { sourceTargets.contains($0.target.name) }
            if directOnly {
                // Direct dependencies only
                let directDeps = sources.flatMap { source in
                    graphTraverser.directTargetDependencies(path: source.path, name: source.target.name).map(\.graphTarget)
                }
                filteredTargets = sources.union(Set(directDeps))
            } else {
                // Transitive dependencies
                let transitiveDeps = transitiveClosure(Array(sources)) { target in
                    Array(graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).map(\.graphTarget))
                }
                filteredTargets = sources.union(transitiveDeps)
            }
        }

        // Apply sink filter: show only what depends on these targets
        if !sinkTargets.isEmpty {
            let sinks = filteredTargets.filter { sinkTargets.contains($0.target.name) }
            let reverseDeps = computeReverseDependencies(
                for: sinks,
                in: filteredTargets,
                graphTraverser: graphTraverser,
                directOnly: directOnly
            )
            filteredTargets = sinks.union(reverseDeps)
        }

        // If neither source nor sink is specified, use transitive closure (original behavior)
        let filteredTargetsAndDependencies: Set<GraphTarget>
        if sourceTargets.isEmpty, sinkTargets.isEmpty {
            filteredTargetsAndDependencies = filteredTargets.union(
                transitiveClosure(Array(filteredTargets)) { target in
                    Array(graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).map(\.graphTarget))
                }
            )
        } else {
            filteredTargetsAndDependencies = filteredTargets
        }

        return filteredTargetsAndDependencies.reduce(into: [GraphTarget: Set<GraphDependency>]()) { result, target in
            if skipExternalDependencies, case .external = target.project.type { return }

            guard let targetDependencies = graphTraverser
                .dependencies[.target(name: target.target.name, path: target.path)]
            else {
                result[target] = Set()
                return
            }

            result[target] = targetDependencies
                .filter { dependency in
                    if skipExternalDependencies, dependency.isExternal(projects) { return false }

                    // Apply type filter
                    if !typeFilter.isEmpty, !typeFilter.contains(dependency.labelName) {
                        return false
                    }

                    return true
                }
        }
    }

    /// Computes reverse dependencies (what depends on the given targets)
    private func computeReverseDependencies(
        for targets: Set<GraphTarget>,
        in allTargets: Set<GraphTarget>,
        graphTraverser: GraphTraverser,
        directOnly: Bool
    ) -> Set<GraphTarget> {
        // Build reverse dependency map: target -> set of targets that depend on it
        var reverseDeps: [GraphTarget: Set<GraphTarget>] = [:]
        for target in allTargets {
            let directDeps = graphTraverser.directTargetDependencies(path: target.path, name: target.target.name)
            for dep in directDeps {
                reverseDeps[dep.graphTarget, default: []].insert(target)
            }
        }

        if directOnly {
            // Return only direct reverse dependencies
            return targets.reduce(into: Set<GraphTarget>()) { result, target in
                if let deps = reverseDeps[target] {
                    result.formUnion(deps)
                }
            }
        } else {
            // Compute transitive reverse closure
            var visited = Set<GraphTarget>()
            var queue = Array(targets)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard !visited.contains(current) else { continue }
                visited.insert(current)

                if let upstream = reverseDeps[current] {
                    for dep in upstream where !visited.contains(dep) {
                        queue.append(dep)
                    }
                }
            }

            // Remove the original targets from visited to return only upstream targets
            return visited.subtracting(targets)
        }
    }
}

extension GraphDependency {
    fileprivate func isExternal(_ projects: [Path.AbsolutePath: XcodeGraph.Project]) -> Bool {
        switch self {
        case let .target(_, path, _):
            if case .external = projects[path]?.type {
                return true
            } else {
                return false
            }
        case .framework, .xcframework, .library, .bundle, .packageProduct, .sdk, .macro:
            return true
        }
    }
}
