import Foundation

public enum Dependency: Codable, Equatable {
    case carthage(name: String, requirement: CarthageRequirement, platforms: Set<Platform>)
    
    private enum Kind: String, Codable {
        case carthage
    }
    
    private enum CodingKeys: String, CodingKey {
        case kind
        case name
        case requirement
        case platforms
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .carthage:
            let name = try container.decode(String.self, forKey: .name)
            let requirement = try container.decode(CarthageRequirement.self, forKey: .requirement)
            let platforms = try container.decode(Set<Platform>.self, forKey: .platforms)
            self = .carthage(name: name, requirement: requirement, platforms: platforms)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .carthage(name, requirement, platforms):
            try container.encode(Kind.carthage, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(requirement, forKey: .requirement)
            try container.encode(platforms, forKey: .platforms)
        }
    }
}
