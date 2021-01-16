import Foundation
import TuistCore

/// A mapper that ensures that the list of projects of the workspace is in sync
/// with the projects available in the graph.
final class UpdateWorkspaceProjectsGraphMapper: GraphMapping {
    func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let graphProjects = Set(graph.projects.map(\.path))
        let workspaceProjects = Set(graph.workspace.projects).intersection(graphProjects)
        let graphXcodeProjPaths = Set(graph.projects.map(\.xcodeProjPath))
        let workspaceXcodeProjPaths = Set(graph.workspace.xcodeProjPaths)
            .intersection(graphXcodeProjPaths)
        var workspace = graph.workspace
        workspace.projects = Array(workspaceProjects.union(graphProjects))
        workspace.xcodeProjPaths = Array(workspaceXcodeProjPaths.union(graphXcodeProjPaths))
        return (graph.with(workspace: workspace), [])
    }
}
