import Foundation
import TSCUtility
import TuistCore

public final class LastUpgradeVersionWorkspaceMapper: WorkspaceMapping {
    public init() {}

    // MARK: - WorkspaceMapping

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        guard let lastXcodeUpgradeCheck = workspace.workspace.generationOptions.lastXcodeUpgradeCheck else {
            return (workspace, [])
        }

        var projects = workspace.projects
        projects.indices.forEach { projects[$0].lastUpgradeCheck = projects[$0].lastUpgradeCheck ?? lastXcodeUpgradeCheck }

        var workspace = workspace
        workspace.projects = projects

        return (workspace, [])
    }
}
