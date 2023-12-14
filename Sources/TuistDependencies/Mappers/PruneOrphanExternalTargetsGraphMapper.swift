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
        let graphTraverser = GraphTraverser(graph: graph)
        let orphanExternalTargets = graphTraverser.allOrphanExternalTargets()

        var graph = graph
        graph.targets = Dictionary(uniqueKeysWithValues: graph.targets.map { projectPath, targets in
            let targets = Dictionary(uniqueKeysWithValues: targets.compactMap { targetName, target -> (String, Target)? in
                let project = graph.projects[projectPath]!
                let graphTarget = GraphTarget(path: projectPath, target: target, project: project)
                if orphanExternalTargets.contains(graphTarget) {
                    return nil
                } else {
                    return (targetName, target)
                }
            })
            return (projectPath, targets)
        })

        return (graph, [])
    }
}
