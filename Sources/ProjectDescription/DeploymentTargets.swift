import Foundation

// MARK: - DeploymentTargets

// A struct representing the minimum deployment versions for each platform.
public struct DeploymentTargets: Hashable, Codable {
    // Minimum deployment version for iOS
    public let iOS: String?
    // Minimum deployment version for macOS
    public let macOS: String?
    // Minimum deployment version for watchOS
    public let watchOS: String?
    // Minimum deployment version for tvOS
    public let tvOS: String?
    // Minimum deployment version for visionOS
    public let visionOS: String?

    public init(iOS: String? = nil, macOS: String? = nil, watchOS: String? = nil, tvOS: String? = nil, visionOS: String? = nil) {
        self.iOS = iOS
        self.macOS = macOS
        self.watchOS = watchOS
        self.tvOS = tvOS
        self.visionOS = visionOS
    }

    // Convenience accessor to retreive a minimum version given a `Platform`
    public subscript(platform: Platform) -> String? {
        switch platform {
        case .iOS:
            return iOS
        case .macOS:
            return macOS
        case .watchOS:
            return watchOS
        case .tvOS:
            return tvOS
        case .visionOS:
            return visionOS
        }
    }

    // Convenience method for `iOS` only minimum version
    public static func iOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(iOS: version)
    }

    // Convenience method for `macOS` only minimum version
    public static func macOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(macOS: version)
    }

    // Convenience method for `watchOS` only minimum version
    public static func watchOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(watchOS: version)
    }

    // Convenience method for `tvOS` only minimum version
    public static func tvOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(tvOS: version)
    }

    // Convenience method for `visionOS` only minimum version
    public static func visionOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(visionOS: version)
    }
}
