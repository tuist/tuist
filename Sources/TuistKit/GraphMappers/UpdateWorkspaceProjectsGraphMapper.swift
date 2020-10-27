import Foundation
import TuistCore

/// A mapper that ensures that the list of projects of the workspace is in sync
/// with the projects available in the graph.
final class UpdateWorkspaceProjectsGraphMapper: GraphMapping {
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphProjects = Set(graph.projects.map(\.path))
        let workspaceProjects = Set(graph.workspace.projects)
        var workspace = graph.workspace
        workspace.projects = Array(workspaceProjects.intersection(graphProjects))
        return (graph.with(workspace: workspace), [])
    }
}
