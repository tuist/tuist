import Foundation

// MARK: - Platform

public enum Platform: String, Codable, Equatable, CaseIterable {
    case iOS = "ios"
    case macOS = "macos"
    case watchOS = "watchos"
    case tvOS = "tvos"
}
