import Foundation

public enum Requirement: Equatable, Codable {
    case upToNextMajor(String)
    case upToNextMinor(String)
    case range(from: String, to: String)
    case exact(String)
    case branch(String)
    case revision(String)
}

// MARK: - Codable

extension Requirement {
    private enum Kind: String, Codable {
        case upToNextMajor
        case upToNextMinor
        case range
        case exact
        case branch
        case revision
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case version
        case from
        case to
        case branch
        case revision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .upToNextMajor:
            let version = try container.decode(String.self, forKey: .version)
            self = .upToNextMajor(version)
        case .upToNextMinor:
            let version = try container.decode(String.self, forKey: .version)
            self = .upToNextMinor(version)
        case .range:
            let from = try container.decode(String.self, forKey: .from)
            let to = try container.decode(String.self, forKey: .to)
            self = .range(from: from, to: to)
        case .exact:
            let version = try container.decode(String.self, forKey: .version)
            self = .exact(version)
        case .branch:
            let branch = try container.decode(String.self, forKey: .branch)
            self = .branch(branch)
        case .revision:
            let revision = try container.decode(String.self, forKey: .revision)
            self = .revision(revision)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .upToNextMajor(version):
            try container.encode(Kind.upToNextMajor, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .upToNextMinor(version):
            try container.encode(Kind.upToNextMinor, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .range(from, to):
            try container.encode(Kind.range, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case let .exact(version):
            try container.encode(Kind.exact, forKey: .kind)
            try container.encode(version, forKey: .version)
        case let .branch(branch):
            try container.encode(Kind.branch, forKey: .kind)
            try container.encode(branch, forKey: .branch)
        case let .revision(revision):
            try container.encode(Kind.revision, forKey: .kind)
            try container.encode(revision, forKey: .revision)
        }
    }
}
