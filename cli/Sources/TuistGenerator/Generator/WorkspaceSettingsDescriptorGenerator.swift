import Foundation
import TuistCore
import XcodeGraph
import XcodeProj

/// Protocol that defines the interface of the workspace settings generation.
protocol WorkspaceSettingsDescriptorGenerating {
    /// Generates the workspace settings based on the workspace generation options.
    ///
    /// - Parameters:
    ///   - workspace: Workspace model.
    func generateWorkspaceSettings(workspace: Workspace) -> WorkspaceSettingsDescriptor?
}

struct WorkspaceSettingsDescriptorGenerator: WorkspaceSettingsDescriptorGenerating {
    func generateWorkspaceSettings(workspace: Workspace) -> WorkspaceSettingsDescriptor? {
        let options = workspace.generationOptions
        let hasCustomDerivedData: Bool = if case .custom = options.derivedDataPath { true } else { false }
        guard options.enableAutomaticXcodeSchemes != nil || hasCustomDerivedData else {
            return nil
        }
        return WorkspaceSettingsDescriptor(
            enableAutomaticXcodeSchemes: options.enableAutomaticXcodeSchemes,
            derivedDataPath: options.derivedDataPath
        )
    }
}
