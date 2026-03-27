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
    private let derivedDataPath: Workspace.GenerationOptions.DerivedDataPath

    var settings: WorkspaceSettings {
        let derivedDataLocationStyle: WorkspaceSettings.DerivedDataLocationStyle?
        let derivedDataCustomLocation: String?
        switch derivedDataPath {
        case .default:
            derivedDataLocationStyle = nil
            derivedDataCustomLocation = nil
        case let .custom(path):
            derivedDataLocationStyle = path.hasPrefix("/") ? .absolutePath : .workspaceRelativePath
            derivedDataCustomLocation = path
        }
        return WorkspaceSettings(
            derivedDataLocationStyle: derivedDataLocationStyle,
            derivedDataCustomLocation: derivedDataCustomLocation,
            autoCreateSchemes: enableAutomaticXcodeSchemes
        )
    }

    public init(
        enableAutomaticXcodeSchemes: Bool?,
        derivedDataPath: Workspace.GenerationOptions.DerivedDataPath = .default
    ) {
        self.enableAutomaticXcodeSchemes = enableAutomaticXcodeSchemes
        self.derivedDataPath = derivedDataPath
    }

    public static func xcsettingsFilePath(relativeToWorkspace workspacePath: AbsolutePath) -> AbsolutePath {
        workspacePath
            .appending(try! RelativePath(validating: "xcshareddata")) // swiftlint:disable:this force_try
            .appending(try! RelativePath(validating: "WorkspaceSettings.xcsettings")) // swiftlint:disable:this force_try
    }
}
