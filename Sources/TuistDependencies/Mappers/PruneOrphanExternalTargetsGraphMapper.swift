import Foundation
import TuistCore
import TuistGraph

/**
 External dependencies might contain targets that are only relevant in development, but that
 that are not necessary when the dependencies are consumed downstream by Tuist projects.
 This graph mappers detects and prunes those targets
 */
public struct PruneOrphanExternalTargetsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: TuistGraph.Graph) async throws -> (TuistGraph.Graph, [TuistCore.SideEffectDescriptor]) {
        logger.debug("Transforming graph \(graph.name): Tree-shaking orphan external targets (e.g. test targets)")

        let graphTraverser = GraphTraverser(graph: graph)
        let orphanExternalTargets = graphTraverser.allOrphanExternalTargets()

        var graph = graph

        graph.projects = graph.projects.mapValues { project in
            var project = project
            project.targets = project.targets.map { target -> Target in
                let project = graph.projects[project.path]!
                let graphTarget = GraphTarget(path: project.path, target: target, project: project)
                var target = target
                if orphanExternalTargets.contains(graphTarget) || target.destinations.isEmpty {
                    target.prune = true
                }
                return target
            }
            return project
        }

        return (graph, [])
    }
}
