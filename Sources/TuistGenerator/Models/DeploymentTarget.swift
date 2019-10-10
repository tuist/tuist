import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget {
    case iOS(String, [DeploymentDevice])
    case macOS(String)
    // TODO: 🙈 Add `watchOS` and `tvOS` support
}
