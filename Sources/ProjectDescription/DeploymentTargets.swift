import Foundation

// MARK: - DeploymentTargets

public struct DeploymentTargets: Hashable, Codable {
    public let iOS: String?
    public let macOS: String?
    public let watchOS: String?
    public let tvOS: String?
    public let visionOS: String?

    public init(iOS: String? = nil, macOS: String? = nil, watchOS: String? = nil, tvOS: String? = nil, visionOS: String? = nil) {
        self.iOS = iOS
        self.macOS = macOS
        self.watchOS = watchOS
        self.tvOS = tvOS
        self.visionOS = visionOS
    }

    public static func iOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(iOS: version)
    }

    public static func macOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(macOS: version)
    }

    public static func watchOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(watchOS: version)
    }

    public static func tvOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(tvOS: version)
    }

    public static func visionOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(visionOS: version)
    }
}
