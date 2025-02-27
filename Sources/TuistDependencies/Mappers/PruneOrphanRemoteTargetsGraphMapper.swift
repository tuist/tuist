import Foundation
import ServiceContextModule
import TuistCore
import XcodeGraph

/**
 Remote dependencies might contain targets that are only relevant in development, but that
 are not necessary when the dependencies are consumed downstream by Tuist projects.
 This graph mapper detects and prunes those targets.
 */
public struct PruneOrphanRemoteTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(
        graph: XcodeGraph.Graph,
        environment: MapperEnvironment
    ) async throws -> (XcodeGraph.Graph, [TuistCore.SideEffectDescriptor], MapperEnvironment) {
        ServiceContext.current?.logger?
            .debug("Transforming graph \(graph.name): Tree-shaking orphan external targets (e.g. test targets)")

        let graphTraverser = GraphTraverser(graph: graph)
        let orphanRemoteTargets = graphTraverser.allOrphanRemoteTargets()

        var graph = graph

        graph.projects = Dictionary(uniqueKeysWithValues: graph.projects.map { projectPath, project in
            var project = project
            project.targets = Dictionary(uniqueKeysWithValues: project.targets.compactMap { _, target -> (String, Target)? in
                let project = graph.projects[projectPath]!
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                var target = target
                if orphanRemoteTargets.contains(graphTarget) || target.destinations.isEmpty {
                    target.prune = true
                }
                return (target.name, target)
            })
            return (projectPath, project)
        })

        return (graph, [], environment)
    }
}
