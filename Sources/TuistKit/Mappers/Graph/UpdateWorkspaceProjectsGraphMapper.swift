import Foundation
import TuistCore
import TuistGraph

/// A mapper that ensures that the list of projects of the workspace is in sync
/// with the projects available in the graph.
final class UpdateWorkspaceProjectsGraphMapper: GraphMapping {
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        var graph = graph
        let graphProjects = Set(graph.projects.map(\.key))
        let workspaceProjects = Set(graph.workspace.projects).intersection(graphProjects)
        var workspace = graph.workspace
        workspace.projects = Array(workspaceProjects.union(graphProjects))
        graph.workspace = workspace
        return (graph, [])
    }
}
