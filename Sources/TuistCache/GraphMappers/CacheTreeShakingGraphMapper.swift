import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class CacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        let sourceTargets: Set<TargetReference> = Set(graph.targets.flatMap { (projectPath, targets) -> [TargetReference] in
            guard graph.projects[projectPath] != nil else { return [] }
            return targets.compactMap { (_, target) -> TargetReference? in
                if target.prune { return nil }
                return TargetReference(projectPath: projectPath, name: target.name)
            }
        })

        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.targets.flatMap(\.value.values).count { return (graph, []) }

        let projects = graph.projects.reduce(into: [AbsolutePath: Project]()) { acc, next in
            let targets = self.treeShake(
                targets: Array(graph.targets[next.key, default: [:]].values),
                path: next.key,
                graph: graph,
                sourceTargets: sourceTargets
            )
            if targets.isEmpty {
                return
            } else {
                let schemes = self.treeShake(
                    schemes: next.value.schemes,
                    sourceTargets: sourceTargets
                )
                acc[next.key] = next.value.with(targets: targets).with(schemes: schemes)
            }
        }

        let workspace = treeShake(
            workspace: graph.workspace,
            projects: Array(projects.values),
            sourceTargets: sourceTargets
        )

        var graph = graph
        graph.workspace = workspace
        graph.projects = projects
        graph.targets = sourceTargets.reduce(into: [AbsolutePath: [String: Target]]()) { acc, targetReference in
            var targets = acc[targetReference.projectPath, default: [:]]
            if let target = graph.targets[targetReference.projectPath, default: [:]][targetReference.name] {
                targets[target.name] = target
            }
            acc[targetReference.projectPath] = targets
        }
        return (graph, [])
    }

    fileprivate func treeShake(workspace: Workspace, projects: [Project], sourceTargets: Set<TargetReference>) -> Workspace {
        let projects = workspace.projects.filter { projects.map(\.path).contains($0) }
        let schemes = treeShake(schemes: workspace.schemes, sourceTargets: sourceTargets)
        var workspace = workspace
        workspace.schemes = schemes
        workspace.projects = projects
        return workspace
    }

    fileprivate func treeShake(targets: [Target], path: AbsolutePath, graph: ValueGraph, sourceTargets: Set<TargetReference>) -> [Target] {
        targets.compactMap { (target) -> Target? in
            guard let target = graph.targets[path, default: [:]][target.name] else { return nil }
            let targetReference = TargetReference(projectPath: path, name: target.name)
            guard sourceTargets.contains(targetReference) else { return nil }
            return target
        }
    }

    fileprivate func treeShake(schemes: [Scheme], sourceTargets: Set<TargetReference>) -> [Scheme] {
        schemes.compactMap { scheme -> Scheme? in
            let buildActionTargets = scheme.buildAction?.targets.filter { sourceTargets.contains($0) } ?? []

            // The scheme contains no buildable targets so we don't include it.
            if buildActionTargets.isEmpty { return nil }

            let testActionTargets = scheme.testAction?.targets.filter { sourceTargets.contains($0.target) } ?? []
            var scheme = scheme
            var buildAction = scheme.buildAction
            var testAction = scheme.testAction
            buildAction?.targets = buildActionTargets
            testAction?.targets = testActionTargets
            scheme.buildAction = buildAction
            scheme.testAction = testAction

            return scheme
        }
    }
}
