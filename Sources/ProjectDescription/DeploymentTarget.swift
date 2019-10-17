import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Codable {
    case iOS(targetVersion: String, devices: DeploymentDevice)
    case macOS(targetVersion: String)
    // TODO: 🙈 Add `watchOS` and `tvOS` support

    private enum Kind: String, Codable {
        case iOS
        case macOS
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
            self = .iOS(targetVersion: version, devices: deploymentDevices)
        case .macOS:
            let version = try container.decode(String.self, forKey: .version)
            self = .macOS(targetVersion: version)
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
        }
    }
}
