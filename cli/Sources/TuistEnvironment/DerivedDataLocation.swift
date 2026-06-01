import Path

/// Describes how Xcode is configured to resolve the DerivedData location, mirroring the
/// `IDECustomDerivedDataLocation` preference in Xcode > Settings > Locations > Derived Data.
///
/// Xcode does not store a separate enum for the Default / Relative / Custom choice. It infers
/// the mode entirely from the shape of the `IDECustomDerivedDataLocation` string: a missing
/// value means the shared default, an absolute path means a custom location, and a relative
/// path is resolved against the workspace directory.
public enum DerivedDataLocation: Equatable, Sendable {
    /// Xcode's shared default location (`~/Library/Developer/Xcode/DerivedData`).
    /// Per-project folders are named `<name>-<hash>`.
    case `default`

    /// An absolute custom location. Per-project folders are named `<name>-<hash>`, using the
    /// same hashing as the default location, so a shared directory can host several projects.
    case custom(AbsolutePath)

    /// A location relative to the workspace directory. Per-project folders are named
    /// `<workspaceName>` without a hash, since the directory lives next to the workspace.
    case relativeToWorkspace(RelativePath)

    /// Classifies the raw value of `IDECustomDerivedDataLocation` (or `IDEDerivedDataPathOverride`)
    /// into a location, mirroring how Xcode interprets the preference string.
    public static func classify(rawLocation: String?) -> DerivedDataLocation {
        guard let rawLocation, !rawLocation.isEmpty else {
            return .default
        }
        if let absolute = try? AbsolutePath(validating: rawLocation) {
            return .custom(absolute)
        }
        if let relative = try? RelativePath(validating: rawLocation) {
            return .relativeToWorkspace(relative)
        }
        return .default
    }
}
