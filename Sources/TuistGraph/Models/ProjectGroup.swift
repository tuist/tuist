import Foundation

public enum ProjectGroup: Hashable, Codable {
    case group(name: String)
}

// MARK: - Codable

extension ProjectGroup {
    private enum Kind: String, Codable {
        case group
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case name
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .group:
            let name = try container.decode(String.self, forKey: .name)
            self = .group(name: name)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .group(name):
            try container.encode(Kind.group, forKey: .kind)
            try container.encode(name, forKey: .name)
        }
    }
}
