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

        let macroSupportTargets: Set<GraphTarget>
        let macroSupportTargetIDs: Set<MacroSupportTargetID>
        if skipMacroSupportTargets {
            // The graph can contain more than one `SwiftCompilerPlugin` target when nested
            // SPM graphs resolve different swift-syntax versions — the transitive closure
            // intentionally walks all of them.
            let roots = Array(graphTraverser.allTargets().filter { $0.target.name == "SwiftCompilerPlugin" })
            if roots.isEmpty {
                macroSupportTargets = []
                macroSupportTargetIDs = []
            } else {
                macroSupportTargets = Set(roots).union(
                    transitiveClosure(roots) { target in
                        let deps = graphTraverser.directTargetDependencies(path: target.path, name: target.target.name)
                        return Array(deps.map(\.graphTarget))
                    }
                )
                macroSupportTargetIDs = Set(macroSupportTargets.map { MacroSupportTargetID(path: $0.path, name: $0.target.name) })
            }
        } else {
            macroSupportTargets = []
            macroSupportTargetIDs = []
        }

        let allTargets: Set<GraphTarget> = skipExternalDependencies ? graphTraverser.allInternalTargets() : graphTraverser
            .allTargets()
        let filteredTargets: Set<GraphTarget> = allTargets.filter { target in
            if skipTestTargets, graphTraverser.dependsOnXCTest(path: target.path, name: target.target.name) {
                return false
            }

            if macroSupportTargets.contains(target) {
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
                if !macroSupportTargets.isEmpty {
                    return deps.filter { !macroSupportTargets.contains($0) }
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
                    if !macroSupportTargetIDs.isEmpty, case let .target(name, path, _) = dependency,
                       macroSupportTargetIDs.contains(MacroSupportTargetID(path: path, name: name)) { return false }
                    return true
                }
        }
    }
}

private struct MacroSupportTargetID: Hashable {
    let path: Path.AbsolutePath
    let name: String
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
