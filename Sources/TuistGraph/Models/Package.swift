import Foundation
import TSCBasic

public enum Package: Equatable, Codable {
    case remote(url: String, requirement: Requirement)
    case local(path: AbsolutePath)
}

// MARK: - Codable

extension Package {
    private enum Kind: String, Codable {
        case remote
        case local
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case url
        case requirement
        case path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .remote:
            let url = try container.decode(String.self, forKey: .url)
            let requirement = try container.decode(Requirement.self, forKey: .requirement)
            self = .remote(url: url, requirement: requirement)
        case .local:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .local(path: path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .remote(url, requirement):
            try container.encode(Kind.remote, forKey: .kind)
            try container.encode(url, forKey: .url)
            try container.encode(requirement, forKey: .requirement)
        case let .local(path):
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
