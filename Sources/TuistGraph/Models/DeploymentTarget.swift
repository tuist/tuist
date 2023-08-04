import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Hashable, Codable {
    case iOS(String)
    case macOS(String)
    case watchOS(String)
    case tvOS(String)
    case visionOS(String)
    
    public var platform: Platform {
        switch self {
        case .iOS:
            return .iOS
        case .macOS:
            return .macOS
        case .tvOS:
            return .tvOS
        case .visionOS:
            return .visionOS
        case .watchOS:
            return .watchOS
        }
    }
    
    public var version: String {
        switch self {
        case let .iOS(version): return version
        case let .macOS(version): return version
        case let .watchOS(version): return version
        case let .tvOS(version): return version
        case let .visionOS(version): return version
        }
    }
}
