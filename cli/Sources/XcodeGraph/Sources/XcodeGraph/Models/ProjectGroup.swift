import Foundation

/// Represents the group structure for organizing files in Xcode.
public enum ProjectGroup: Hashable, Codable, Sendable {
    /// No group - files will be placed at the root level of the Xcode project.
    case none
    /// A named group - files will be placed inside this group.
    case group(name: String)
    
    /// Returns the group name if this is a `.group` case, nil otherwise.
    public var name: String? {
        switch self {
        case .none:
            return nil
        case let .group(name):
            return name
        }
    }
}
