// MARK: - Platform

/// A supported platform representation.
public enum Platform: String, Codable, Equatable, CaseIterable, Sendable {
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

/// A supported Swift Package Manager platform representation.
public enum PackagePlatform: String, Codable, Equatable, CaseIterable, Sendable {
    /// The iOS platform
    case iOS = "ios"
    /// The macOS platform
    case macOS = "macos"
    /// The Mac Catalyst platform
    case macCatalyst = "maccatalyst"
    /// The watchOS platform
    case watchOS = "watchos"
    /// The tvOS platform
    case tvOS = "tvos"
    /// The visionOS platform
    case visionOS = "visionos"
}
