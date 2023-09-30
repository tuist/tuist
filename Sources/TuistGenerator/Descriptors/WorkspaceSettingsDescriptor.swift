import Foundation
import TSCBasic
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
    private let enableAutomaticXcodeSchemes: Bool?

    var settings: WorkspaceSettings {
        WorkspaceSettings(autoCreateSchemes: enableAutomaticXcodeSchemes)
    }

    public init(enableAutomaticXcodeSchemes: Bool?) {
        self.enableAutomaticXcodeSchemes = enableAutomaticXcodeSchemes
    }
}

extension WorkspaceSettingsDescriptor {
    public static func xcsettingsFilePath(relativeToWorkspace workspacePath: AbsolutePath) -> AbsolutePath {
        workspacePath
            .appending(try! RelativePath(validating: "xcshareddata")) // swiftlint:disable:this force_try
            .appending(try! RelativePath(validating: "WorkspaceSettings.xcsettings")) // swiftlint:disable:this force_try
    }
}
