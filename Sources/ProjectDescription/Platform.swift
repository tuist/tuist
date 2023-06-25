import Foundation

// MARK: - Platform

/// A supported platform representation.
public enum Platform: String, Codable, Equatable, CaseIterable {
    /// The iOS platform
    case iOS = "ios"
    /// The macOS platform
    case macOS = "macos"
    /// The watchOS platform
    case watchOS = "watchos"
    /// The tvOS platform
    case tvOS = "tvos"
    /// The visionOS platform
    case visionOS = "visionos"
}
