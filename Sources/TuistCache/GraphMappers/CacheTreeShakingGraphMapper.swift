import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class CacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        let sourceTargets: Set<TargetReference> = Set(graph.targets.flatMap { (projectPath, targets) -> [TargetReference] in
            guard let project = graph.projects[projectPath] else { return [] }
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

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let sourceTargets: Set<TargetReference> = graph.targets.reduce(into: Set<TargetReference>()) { acc, next in
            acc.formUnion(next.value.filter { !$0.target.prune }.map { TargetReference(projectPath: $0.path, name: $0.name) })
        }
        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.targets.flatMap(\.value).count { return (graph, []) }

        let projects = graph.projects.compactMap { (project) -> Project? in
            let targets = self.treeShake(
                targets: project.targets,
                path: project.path,
                graph: graph,
                sourceTargets: sourceTargets
            )

            // If the project has no targets we remove the project.
            if targets.isEmpty {
                return nil
            } else {
                let schemes = self.treeShake(
                    schemes: project.schemes,
                    sourceTargets: sourceTargets
                )
                return project.with(targets: targets).with(schemes: schemes)
            }
        }

        let workspace = treeShake(
            workspace: graph.workspace,
            projects: projects,
            sourceTargets: sourceTargets
        )

        let graph = graph
            .with(projects: projects)
            .with(workspace: workspace)
            .with(targets: sourceTargets.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, targetReference in
                var targets = acc[targetReference.projectPath, default: []]
                if let target = graph.target(path: targetReference.projectPath, name: targetReference.name) {
                    targets.append(target)
                }
                acc[targetReference.projectPath] = targets
            })

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

    fileprivate func treeShake(targets: [Target], path: AbsolutePath, graph: Graph, sourceTargets: Set<TargetReference>) -> [Target] {
        targets.compactMap { (target) -> Target? in
            guard let targetNode = graph.target(path: path, name: target.name) else { return nil }
            let targetReference = TargetReference(projectPath: targetNode.path, name: targetNode.name)
            guard sourceTargets.contains(targetReference) else { return nil }
            return target
        }
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
