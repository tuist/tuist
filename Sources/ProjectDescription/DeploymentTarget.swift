import Foundation

// MARK: - DeploymentTarget

/// A supported minimum deployment target.
public enum DeploymentTarget: Codable, Hashable {
    /// The minimum iOS version, the list of devices your product will support, and whether or not the target should run on mac devices.
    case iOS(targetVersion: String, devices: DeploymentDevice, supportsMacDesignedForIOS: Bool = true)
    /// The minimum macOS version your product will support.
    case macOS(targetVersion: String)
    /// The minimum watchOS version your product will support.
    case watchOS(targetVersion: String)
    /// The minimum tvOS version your product will support.
    case tvOS(targetVersion: String)
    /// The minimum visionOS version your product will support.
    case visionOS(targetVersion: String)

    private enum Kind: String, Codable {
        case iOS
        case macOS
        case watchOS
        case tvOS
        case visionOS
    }

    /// The target platform version
    public var targetVersion: String {
        switch self {
        case let .iOS(targetVersion, _, _), let .macOS(targetVersion), let .watchOS(targetVersion),
             let .tvOS(targetVersion), let .visionOS(targetVersion):
            return targetVersion
        }
    }
}
