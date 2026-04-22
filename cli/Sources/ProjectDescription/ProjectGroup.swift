/// Represents the files group configuration for a project in Xcode.
///
/// Use `.none` to omit the files group completely (files appear at root level).
/// Use `.group(name:)` to customize the group name.
public enum ProjectGroup: Codable, Equatable, Sendable {
    /// No group - files will be placed at root level without a container group
    case none
    /// Group with a custom name
    case group(name: String)
}
