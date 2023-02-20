import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Hashable, Codable {
    case iOS(String, DeploymentDevice)
    case macOS(String)
    case watchOS(String)
    case tvOS(String)
    
    public var platform: Platform {
        switch self {
        case .iOS: return .iOS
        case .macOS: return .macOS
        case .tvOS: return .tvOS
        case .watchOS: return .watchOS
        }
    }


    public var version: String {
        switch self {
        case let .iOS(version, _): return version
        case let .macOS(version): return version
        case let .watchOS(version): return version
        case let .tvOS(version): return version
        }
    }
}
