import Foundation
import Path
import TuistCore
import XcodeGraph

public final class TreeShakePrunedTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        logger.debug("Transforming graph \(graph.name): Tree-shaking nodes")
        let sourceTargets: Set<TargetReference> = Set(graph.projects.flatMap { projectPath, project -> [TargetReference] in
            return project.targets.compactMap { _, target -> TargetReference? in
                if target.prune { return nil }
                return TargetReference(projectPath: projectPath, name: target.name)
            }
        })

        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.projects.values.flatMap(\.targets.values).count { return (graph, [], environment) }

        let projects = graph.projects.reduce(into: [AbsolutePath: Project]()) { acc, next in
            let targets = self.treeShake(
                targets: Array(next.value.targets.values),
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
                var project = next.value
                project.schemes = schemes
                project.targets = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
                acc[next.key] = project
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
        return (graph, [], environment)
    }

    fileprivate func treeShake(workspace: Workspace, projects: [Project], sourceTargets: Set<TargetReference>) -> Workspace {
        let projects = workspace.projects.filter { projects.map(\.path).contains($0) }
        let schemes = treeShake(schemes: workspace.schemes, sourceTargets: sourceTargets)
        var workspace = workspace
        workspace.schemes = schemes
        workspace.projects = projects
        return workspace
    }

    fileprivate func treeShake(
        targets: [Target],
        path: AbsolutePath,
        graph: Graph,
        sourceTargets: Set<TargetReference>
    ) -> [Target] {
        targets.compactMap { target -> Target? in
            guard let target = graph.projects[path]?.targets[target.name] else { return nil }
            let targetReference = TargetReference(projectPath: path, name: target.name)
            guard sourceTargets.contains(targetReference) else { return nil }
            return target
        }
    }

    fileprivate func treeShake(schemes: [Scheme], sourceTargets: Set<TargetReference>) -> [Scheme] {
        schemes.compactMap { scheme -> Scheme? in
            var scheme = scheme

            if let buildAction = scheme.buildAction {
                scheme.buildAction?.targets = buildAction.targets.filter(sourceTargets.contains)
            }

            if let testAction = scheme.testAction {
                scheme.testAction?.targets = testAction.targets.filter { sourceTargets.contains($0.target) }
                scheme.testAction?.codeCoverageTargets = testAction.codeCoverageTargets.filter(sourceTargets.contains)
            }

            let hasBuildTargets = !(scheme.buildAction?.targets ?? []).isEmpty
            let hasTestTargets = !(scheme.testAction?.targets ?? []).isEmpty
            let hasTestPlans = !(scheme.testAction?.testPlans ?? []).isEmpty
            guard hasBuildTargets || hasTestTargets || hasTestPlans else {
                return nil
            }

            if let expandVariableFromTarget = scheme.runAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                return nil
            }

            if let expandVariableFromTarget = scheme.testAction?.expandVariableFromTarget,
               !sourceTargets.contains(expandVariableFromTarget)
            {
                return nil
            }

            return scheme
        }
    }
}
