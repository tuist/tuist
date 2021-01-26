import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class CacheTreeShakingGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        let sourceTargets: Set<TargetReference> = graph.targets.reduce(into: Set<TargetReference>()) { acc, next in
            let targets = next.value.values
            let projectPath = next.key

            acc.formUnion(targets.filter { !$0.prune }.map { TargetReference(projectPath: projectPath, name: $0.name) })
        }
        // If the number of source targets matches the number of targets in the graph there's nothing to be pruned.
        if sourceTargets.count == graph.targets.flatMap(\.value).count { return (graph, []) }

        var treeShakedProjects: [AbsolutePath: Project] = [:]
        var treeShakedTargets: [AbsolutePath: [String: Target]] = [:]

        graph.projects.forEach { projectPath, project in
            let projectTreeShakedTargets = self.treeShake(targets: Array(graph.targets[projectPath, default: [:]].values),
                                                          path: projectPath,
                                                          graph: graph,
                                                          sourceTargets: sourceTargets)

            // If the project has no targets we remove the project.
            if projectTreeShakedTargets.isEmpty {
                treeShakedTargets[projectPath] = [:]
            } else {
                var project = project
                project.schemes = self.treeShake(schemes: project.schemes,
                                                 sourceTargets: sourceTargets)
                treeShakedProjects[projectPath] = project
                treeShakedTargets[projectPath] = projectTreeShakedTargets.reduce(into: [String: Target]()) { $0[$1.name] = $1 }
            }
        }

        let treeShakedWorkspace = treeShake(workspace: graph.workspace,
                                            projects: Array(treeShakedProjects.values),
                                            sourceTargets: sourceTargets)

        var treeShakedGraph = graph
        treeShakedGraph.projects = treeShakedProjects
        treeShakedGraph.targets = treeShakedTargets
        treeShakedGraph.workspace = treeShakedWorkspace

        return (treeShakedGraph, [])
    }

    fileprivate func treeShake(workspace: Workspace, projects: [Project], sourceTargets: Set<TargetReference>) -> Workspace {
        let projects = workspace.projects.filter { projects.map(\.path).contains($0) }
        let schemes = treeShake(schemes: workspace.schemes, sourceTargets: sourceTargets)
        var workspace = workspace
        workspace.schemes = schemes
        workspace.projects = projects
        return workspace
    }

    fileprivate func treeShake(targets: [Target], path: AbsolutePath, graph _: ValueGraph, sourceTargets: Set<TargetReference>) -> [Target] {
        targets.compactMap { (target) -> Target? in
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
