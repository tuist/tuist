import Foundation
import Path
import TSCBasic
import TuistCore
import XcodeGraph

extension XcodeGraph.Graph {
    /// Filters the project graph
    /// - Parameters:
    /// - Returns: Filtered graph targets and dependencies
    public func filter(
        skipTestTargets: Bool,
        skipExternalDependencies: Bool,
        skipMacroSupportTargets: Bool,
        platformToFilter: Platform?,
        targetsToFilter: [String]
    ) -> [GraphTarget: Set<GraphDependency>] {
        let graphTraverser = GraphTraverser(graph: self)

        // Compute the set of macro support target names to exclude:
        // SwiftCompilerPlugin and everything it transitively depends on.
        let macroSupportTargetNames: Set<String>
        if skipMacroSupportTargets {
            let roots = Array(graphTraverser.allTargets().filter { $0.target.name == "SwiftCompilerPlugin" })
            let allMacroSupportTargets = Set(roots).union(
                transitiveClosure(roots) { target in
                    Array(graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).map(\.graphTarget))
                }
            )
            macroSupportTargetNames = Set(allMacroSupportTargets.map(\.target.name))
        } else {
            macroSupportTargetNames = []
        }

        let allTargets: Set<GraphTarget> = skipExternalDependencies ? graphTraverser.allInternalTargets() : graphTraverser
            .allTargets()
        let filteredTargets: Set<GraphTarget> = allTargets.filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if !macroSupportTargetNames.isEmpty, macroSupportTargetNames.contains(target.target.name) {
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

        let filteredTargetsAndDependencies: Set<GraphTarget> = filteredTargets.union(
            transitiveClosure(Array(filteredTargets)) { target in
                let deps = graphTraverser.directTargetDependencies(path: target.path, name: target.target.name).map(\.graphTarget)
                if !macroSupportTargetNames.isEmpty {
                    return deps.filter { !macroSupportTargetNames.contains($0.target.name) }
                }
                return Array(deps)
            }
        )

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
                    if !macroSupportTargetNames.isEmpty, case let .target(name, _, _) = dependency,
                       macroSupportTargetNames.contains(name) { return false }
                    return true
                }
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
        case .framework, .xcframework, .library, .bundle, .packageProduct, .sdk, .macro, .foreignBuildOutput:
            return true
        }
    }
}
