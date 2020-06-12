import Foundation
import TuistCore

/// A graph mapper that inserts a pre and post build phase to every target of the graph to send
/// build insights to the cloud.
public class CloudInsightsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let mapper = TargetNodeGraphMapper { (targetNode) -> TargetNode in
            var target = targetNode.target
            var actions = target.actions
            actions.append(.init(name: "[Tuist] Track target build start",
                                 order: .pre,
                                 tool: "tuist",
                                 path: nil,
                                 arguments: ["cloud", "start-target-build"]))
            actions.append(.init(name: "[Tuist] Track target build finish",
                                 order: .post,
                                 tool: "tuist",
                                 path: nil,
                                 arguments: ["cloud", "finish-target-build"]))
            target = target.with(actions: actions)
            return TargetNode(project: targetNode.project, target: target, dependencies: targetNode.dependencies)
        }
        return mapper.map(graph: graph)
    }

    public func map(graph: ValueGraph) throws -> (ValueGraph, [SideEffectDescriptor]) {
        let targets = graph.targets.mapValues { (targets: [String: Target]) in
            targets.mapValues { (target: Target) -> Target in
                var actions = target.actions
                actions.append(.init(name: "[Tuist] Track target build start",
                                     order: .pre,
                                     tool: "tuist",
                                     path: nil,
                                     arguments: ["cloud", "start-target-build"]))
                actions.append(.init(name: "[Tuist] Track target build finish",
                                     order: .post,
                                     tool: "tuist",
                                     path: nil,
                                     arguments: ["cloud", "finish-target-build"]))
                return target.with(actions: actions)
            }
        }
        let graph = ValueGraph(projects: graph.projects,
                               packages: graph.packages,
                               targets: targets,
                               dependencies: graph.dependencies)
        return (graph, [])
    }
}
