import Foundation
import XcodeProj

/// Workspace Settings Descriptor
///
/// Contains the information needed to generate shared workspace settings.
///
/// When included in `WorkspaceDescriptor`, it is used to generate the
/// `WorkspaceSettings.xcsettings` file under `xcshareddata`.
///
/// - seealso: `WorkspaceDescriptor`
public struct WorkspaceSettingsDescriptor: Equatable {
    public var automaticSchemeGeneration: Bool?

    public init(automaticSchemeGeneration: Bool?) {
        self.automaticSchemeGeneration = automaticSchemeGeneration
    }
}
