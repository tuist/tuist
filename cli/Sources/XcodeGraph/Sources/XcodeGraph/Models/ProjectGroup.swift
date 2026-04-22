import Foundation

public enum ProjectGroup: Hashable, Codable, Sendable {
    /// No group - files will be placed at root level without a container group
    case none
    /// Group with a custom name
    case group(name: String)
}
