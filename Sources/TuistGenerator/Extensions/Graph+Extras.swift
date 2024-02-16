import Foundation
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.Graph {
    /// Filters the project graph
    /// - Parameters:
    /// - Returns: Filtered graph targets and dependencies
    public func filter(
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        platformToFilter: Platform?,
        targetsToFilter: [String],
        excludeTargetsContaining: [String]
    ) -> [GraphTarget: Set<GraphDependency>] {
        let graphTraverser = GraphTraverser(graph: self)

        let allTargets: Set<GraphTarget> = skipExternalDependencies ? graphTraverser.allInternalTargets() : graphTraverser
            .allTargets()
        let filteredTargets: Set<GraphTarget> = allTargets.filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if let platformToFilter, !target.target.supports(platformToFilter) {
                return false
            }

            if !targetsToFilter.isEmpty, !targetsToFilter.contains(target.target.name) {
                return false
            }

            if target.target.name.matchesAnyPattern(excludeTargetsContaining) {
                return false
            }

            return true
        }

        let filteredTargetsAndDependencies: Set<GraphTarget> = filteredTargets.union(
            transitiveClosure(Array(filteredTargets)) { target in
                Array(
                    graphTraverser.directTargetDependencies(path: target.path, name: target.target.name)
                        .compactMap { dependency in
                            let dependencyTarget = dependency.graphTarget

                            if dependencyTarget.target.name.matchesAnyPattern(excludeTargetsContaining) {
                                return nil
                            }
                            return dependencyTarget
                        }
                )
            }
        )

        return filteredTargetsAndDependencies.reduce(into: [GraphTarget: Set<GraphDependency>]()) { result, target in
            if skipExternalDependencies, target.project.isExternal { return }

            guard let targetDependencies = graphTraverser.dependencies[.target(name: target.target.name, path: target.path)]
            else { return }

            result[target] = targetDependencies
                .filter { dependency in
                    if dependency.name.matchesAnyPattern(excludeTargetsContaining) {
                        return false
                    }

                    if skipExternalDependencies, dependency.isExternal(projects) { return false }
                    return true
                }
        }
    }
}

extension GraphDependency {
    fileprivate func isExternal(_ projects: [AbsolutePath: TuistGraph.Project]) -> Bool {
        switch self {
        case let .target(_, path):
            return projects[path]?.isExternal ?? false
        case .framework, .xcframework, .library, .bundle, .packageProduct, .sdk, .macro:
            return true
        }
    }
}

extension String {
    fileprivate func matchesAnyPattern(_ patterns: [String]) -> Bool {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(startIndex..., in: self)
                if regex.firstMatch(in: self, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }
}
