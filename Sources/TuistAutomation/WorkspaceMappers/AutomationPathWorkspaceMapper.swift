import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Updates path of workspace to point to where automation workspace should be generated
public final class AutomationPathWorkspaceMapper: WorkspaceMapping {
    let workspaceDirectory: AbsolutePath

    public init(
        workspaceDirectory: AbsolutePath
    ) {
        self.workspaceDirectory = workspaceDirectory
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        workspace.workspace.xcWorkspacePath = workspaceDirectory.appending(component: "\(workspace.workspace.name).xcworkspace")
        let mappedProjects = try workspace.projects.map(map(project:))
        workspace.projects = mappedProjects.map(\.0)
        return (
            workspace,
            [
                .directory(
                    DirectoryDescriptor(
                        path: workspaceDirectory,
                        state: .present
                    )
                ),
            ] + mappedProjects.flatMap(\.1)
        )
    }

    // MARK: - Helpers

    private func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        var project = project
        let xcodeProjBasename = project.xcodeProjPath.basename
        project.xcodeProjPath = workspaceDirectory.appending(component: xcodeProjBasename)
        return (
            project,
            []
        )
    }
}
