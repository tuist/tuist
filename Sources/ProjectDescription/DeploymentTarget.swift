import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Codable, Hashable {
    case iOS(targetVersion: String, devices: DeploymentDevice)
    case macOS(targetVersion: String)
    case watchOS(targetVersion: String)
    case tvOS(targetVersion: String)

    private enum Kind: String, Codable {
        case iOS
        case macOS
        case watchOS
        case tvOS
    }
}
