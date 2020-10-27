import Foundation
import TSCBasic
import TuistCore

public final class CacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let sourceTargets: Set<TargetReference> = graph.targets.reduce(into: Set<TargetReference>()) { acc, next in
            acc.formUnion(next.value.filter { !$0.prune }.map { TargetReference(projectPath: $0.path, name: $0.name) })
        }
        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.targets.count { return (graph, []) }

        let projects = graph.projects.compactMap { (project) -> Project? in
            let targets = self.treeShake(targets: project.targets,
                                         path: project.path,
                                         graph: graph,
                                         sourceTargets: sourceTargets)

            // If the project has no targets we remove the project.
            if targets.isEmpty {
                return nil
            } else {
                let schemes = self.treeShake(schemes: project.schemes,
                                             sourceTargets: sourceTargets)
                return project.with(targets: targets).with(schemes: schemes)
            }
        }

        let graph = graph
            .with(projects: projects)
            .with(targets: sourceTargets.reduce(into: [AbsolutePath: [TargetNode]]()) { acc, targetReference in
                var targets = acc[targetReference.projectPath, default: []]
                if let target = graph.target(path: targetReference.projectPath, name: targetReference.name) {
                    targets.append(target)
                }
                acc[targetReference.projectPath] = targets
            })

        return (graph, [])
    }

    fileprivate func treeShake(targets: [Target], path: AbsolutePath, graph: Graph, sourceTargets: Set<TargetReference>) -> [Target] {
        targets.compactMap { (target) -> Target? in
            guard let targetNode = graph.target(path: path, name: target.name) else { return nil }
            let targetReference = TargetReference(projectPath: targetNode.path, name: targetNode.name)
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
