import Foundation
import TuistCore
import XcodeGraph

/// A mapper that ensures that the list of projects of the workspace is in sync
/// with the projects available in the graph.
public final class UpdateWorkspaceProjectsGraphMapper: GraphMapping {
    public init() {}

    public func map(graph: Graph, environment: MapperEnvironment) throws -> (Graph, [SideEffectDescriptor], MapperEnvironment) {
        logger.debug("Transforming graph \(graph.name): Aligning workspace projects with the graph's")

        var graph = graph
        let graphProjects = Set(graph.projects.map(\.key))
        let workspaceProjects = Set(graph.workspace.projects).intersection(graphProjects)
        var workspace = graph.workspace
        workspace.projects = Array(workspaceProjects.union(graphProjects))
        graph.workspace = workspace
        return (graph, [], environment)
    }
}
