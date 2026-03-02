import Foundation
import Path
import XcodeGraph
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
    private let derivedDataLocationStyle: Workspace.GenerationOptions.DerivedDataLocationStyle?
    private let derivedDataCustomLocation: String?

    var settings: WorkspaceSettings {
        WorkspaceSettings(
            derivedDataLocationStyle: derivedDataLocationStyle.map {
                switch $0 {
                case .default: return .default
                case .absolutePath: return .absolutePath
                case .workspaceRelativePath: return .workspaceRelativePath
                }
            },
            derivedDataCustomLocation: derivedDataCustomLocation,
            autoCreateSchemes: enableAutomaticXcodeSchemes
        )
    }

    public init(
        enableAutomaticXcodeSchemes: Bool?,
        derivedDataLocationStyle: Workspace.GenerationOptions.DerivedDataLocationStyle? = nil,
        derivedDataCustomLocation: String? = nil
    ) {
        self.enableAutomaticXcodeSchemes = enableAutomaticXcodeSchemes
        self.derivedDataLocationStyle = derivedDataLocationStyle
        self.derivedDataCustomLocation = derivedDataCustomLocation
    }

    public static func xcsettingsFilePath(relativeToWorkspace workspacePath: AbsolutePath) -> AbsolutePath {
        workspacePath
            .appending(try! RelativePath(validating: "xcshareddata")) // swiftlint:disable:this force_try
            .appending(try! RelativePath(validating: "WorkspaceSettings.xcsettings")) // swiftlint:disable:this force_try
    }
}
