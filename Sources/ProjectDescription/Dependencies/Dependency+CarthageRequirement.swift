import Foundation

public extension Dependency {
    enum CarthageRequirement: Codable, Equatable {
        case exact(Version)
        case upToNextMajor(Version)
        case upToNextMinor(Version)
        case branch(String)
        case revision(String)

        private enum Kind: String, Codable {
            case exact
            case upToNextMajor
            case upToNextMinor
            case branch
            case revision
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case version
            case branch
            case revision
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .exact:
                let version = try container.decode(Version.self, forKey: .version)
                self = .exact(version)
            case .upToNextMajor:
                let version = try container.decode(Version.self, forKey: .version)
                self = .upToNextMajor(version)
            case .upToNextMinor:
                let version = try container.decode(Version.self, forKey: .version)
                self = .upToNextMinor(version)
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
            case let .exact(version):
                try container.encode(Kind.exact, forKey: .kind)
                try container.encode(version, forKey: .version)
            case let .upToNextMajor(version):
                try container.encode(Kind.upToNextMajor, forKey: .kind)
                try container.encode(version, forKey: .version)
            case let .upToNextMinor(version):
                try container.encode(Kind.upToNextMinor, forKey: .kind)
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
}
