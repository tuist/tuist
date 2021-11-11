import Foundation
import TSCUtility
import TuistCore

public final class LastUpgradeVersionWorkspaceMapper: WorkspaceMapping {
    let lastUpgradeVersion: Version

    public init(lastUpgradeVersion: Version) {
        self.lastUpgradeVersion = lastUpgradeVersion
    }

    // MARK: - WorkspaceMapping

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var projects = workspace.projects
        projects.indices.forEach { projects[$0].lastUpgradeCheck = lastUpgradeVersion }

        var workspace = workspace
        workspace.workspace.lastUpgradeCheck = lastUpgradeVersion
        workspace.projects = projects

        return (workspace, [])
    }
}
