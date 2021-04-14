import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Equatable, Codable {
    case iOS(String, DeploymentDevice)
    case macOS(String)
    case watchOS(String)
    case tvOS(String)

    public var platform: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .watchOS: return "watchOS"
        case .tvOS: return "tvOS"
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

// MARK: - Codable

extension DeploymentTarget {
    private enum Kind: String, Codable {
        case iOS
        case macOS
        case watchOS
        case tvOS
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case version
        case deploymentDevices
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .iOS:
            let version = try container.decode(String.self, forKey: .version)
            let deploymentDevices = try container.decode(DeploymentDevice.self, forKey: .deploymentDevices)
            self = .iOS(version, deploymentDevices)
        case .macOS:
            let version = try container.decode(String.self, forKey: .version)
            self = .macOS(version)
        case .watchOS:
            let version = try container.decode(String.self, forKey: .version)
            self = .watchOS(version)
        case .tvOS:
            let version = try container.decode(String.self, forKey: .version)
            self = .tvOS(version)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .iOS(version, deploymentDevices):
            try container.encode(Kind.iOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
            try container.encode(deploymentDevices, forKey: .deploymentDevices)
        case let .macOS(version):
            try container.encode(Kind.macOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .watchOS(version):
            try container.encode(Kind.watchOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .tvOS(version):
            try container.encode(Kind.tvOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        }
    }
}
