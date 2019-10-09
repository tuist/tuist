import Foundation

// MARK: - DeploymentTarget

public enum DeploymentTarget: Codable {
    case iOS(String, [DeploymentDevice])
    case macOS(String)
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
            let deploymentDevices = try container.decode([DeploymentDevice].self, forKey: .deploymentDevices)
            self = .iOS(version, deploymentDevices)
        case .macOS:
            let version = try container.decode(String.self, forKey: .version)
            self = .macOS(version)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .iOS(let version, let deploymentDevices):
            try container.encode(Kind.iOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
            try container.encode(deploymentDevices, forKey: .deploymentDevices)
        case .macOS(let version):
            try container.encode(Kind.macOS.self, forKey: .kind)
            try container.encode(version, forKey: .version)
        }
    }
}
