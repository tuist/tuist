import Foundation

// MARK: - DeploymentTargets

/// A struct representing the minimum deployment versions for each platform.
public struct DeploymentTargets: Hashable, Codable {
    /// Minimum deployment version for iOS
    public var iOS: String?
    /// Minimum deployment version for macOS
    public var macOS: String?
    /// Minimum deployment version for watchOS
    public var watchOS: String?
    /// Minimum deployment version for tvOS
    public var tvOS: String?
    /// Minimum deployment version for visionOS
    public var visionOS: String?

    public static func deploymentTargets(
        iOS: String? = nil,
        macOS: String? = nil,
        watchOS: String? = nil,
        tvOS: String? = nil,
        visionOS: String? = nil
    ) -> Self {
        self.init(
            iOS: iOS,
            macOS: macOS,
            watchOS: watchOS,
            tvOS: tvOS,
            visionOS: visionOS
        )
    }

    /// Convenience accessor to retreive a minimum version given a `Platform`
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

    /// Convenience method for `iOS` only minimum version
    public static func iOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(iOS: version)
    }

    /// Convenience method for `macOS` only minimum version
    public static func macOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(macOS: version)
    }

    /// Convenience method for `watchOS` only minimum version
    public static func watchOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(watchOS: version)
    }

    /// Convenience method for `tvOS` only minimum version
    public static func tvOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(tvOS: version)
    }

    /// Convenience method for `visionOS` only minimum version
    public static func visionOS(_ version: String) -> DeploymentTargets {
        DeploymentTargets(visionOS: version)
    }
}

extension DeploymentTargets: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Platform, String)...) {
        let dictionary = Dictionary(uniqueKeysWithValues: elements)
             
        self.init(iOS: dictionary[.iOS],
                  macOS: dictionary[.macOS],
                  watchOS: dictionary[.watchOS],
                  tvOS: dictionary[.tvOS],
                  visionOS: dictionary[.visionOS])
    }
}
