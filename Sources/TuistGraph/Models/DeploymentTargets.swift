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

    public var configuredVersions: [(platform: Platform, versionString: String)] {
        var versions = [(Platform, String)]()

        if let iOS {
            versions.append((.iOS, iOS))
        }

        if let macOS {
            versions.append((.macOS, macOS))
        }

        if let watchOS {
            versions.append((.watchOS, watchOS))
        }

        if let tvOS {
            versions.append((.tvOS, tvOS))
        }

        if let visionOS {
            versions.append((.visionOS, visionOS))
        }

        return versions
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

    public static func empty() -> DeploymentTargets {
        DeploymentTargets()
    }
}
