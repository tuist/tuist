import Foundation

/// A minimum deployment version representation
public enum MinimumDeployment: Codable, Hashable {
    /// The minimum iOS version your product will support.
    case iOS(targetVersion: String)
    /// The minimum macOS version your product will support.
    case macOS(targetVersion: String)
    /// The minimum watchOS version your product will support.
    case watchOS(targetVersion: String)
    /// The minimum tvOS version your product will support.
    case tvOS(targetVersion: String)
    
    /// The target platform version
    public var targetVersion: String {
        switch self {
        case let .iOS(targetVersion), let .macOS(targetVersion), let .watchOS(targetVersion), let .tvOS(targetVersion):
            return targetVersion
        }
    }
    
    public var platform: Platform {
        switch self {
        case .iOS:
            return .iOS
        case .macOS:
            return .macOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        }
    }
}
