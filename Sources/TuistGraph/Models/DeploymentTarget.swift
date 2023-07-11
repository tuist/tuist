import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Hashable, Codable {
    case iOS(String, DeploymentDevice, supportsMacDesignedForIOS: Bool)
    case macOS(String)
    case watchOS(String)
    case tvOS(String)
    case visionOS(String)

    public var platform: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .watchOS: return "watchOS"
        case .tvOS: return "tvOS"
        case .visionOS: return "visionOS"
        }
    }

    public var version: String {
        switch self {
        case let .iOS(version, _, _): return version
        case let .macOS(version): return version
        case let .watchOS(version): return version
        case let .tvOS(version): return version
        case let .visionOS(version): return version
        }
    }
}
