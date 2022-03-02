import Foundation

// MARK: - Platform

/// The platform type represents the platform a target is built for. It can be any of the following types.
public enum Platform: String, Codable, Equatable, CaseIterable {
    /// The iOS platform
    case iOS = "ios"
    /// The macOS platform
    case macOS = "macos"
    /// The watchOS platform
    case watchOS = "watchos"
    /// The tvOS platform
    case tvOS = "tvos"
}
