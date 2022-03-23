import Foundation

// MARK: - DeploymentTarget

/// A supported minimum deployment target.
public enum DeploymentTarget: Codable, Hashable {
    /// The minimum iOS version and the list of devices your product will support.
    case iOS(targetVersion: String, devices: DeploymentDevice)
    /// The minimum macOS version your product will support.
    case macOS(targetVersion: String)
    /// The minimum watchOS version your product will support.
    case watchOS(targetVersion: String)
    /// The minimum tvOS version your product will support.
    case tvOS(targetVersion: String)

    private enum Kind: String, Codable {
        case iOS
        case macOS
        case watchOS
        case tvOS
    }
}
