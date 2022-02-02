import Foundation
import TuistCore
import TuistGraph
import TuistSupport
import XcodeProj

/// Protocol that defines the interface of the workspace settings generation.
protocol WorkspaceSettingsDescriptorGenerating {
    /// Generates the workspace settings based on the workspace generation options.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    func generateWorkspaceSettings(workspace: Workspace) -> WorkspaceSettingsDescriptor?
}

final class WorkspaceSettingsDescriptorGenerator: WorkspaceSettingsDescriptorGenerating {
    func generateWorkspaceSettings(workspace: Workspace) -> WorkspaceSettingsDescriptor? {
        workspace.generationOptions.automaticXcodeSchemes.value.flatMap {
            WorkspaceSettingsDescriptor(automaticXcodeSchemes: $0)
        }
    }
}
