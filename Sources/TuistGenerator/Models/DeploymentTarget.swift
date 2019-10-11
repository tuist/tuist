import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget {
    case iOS(String, [DeploymentDevice])
    case macOS(String)
    // TODO: 🙈 Add `watchOS` and `tvOS` support

    public var platform: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        }
    }
}
