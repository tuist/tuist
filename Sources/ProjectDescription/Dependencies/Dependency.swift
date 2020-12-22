import Foundation

public enum Dependency: Codable, Equatable {
    case carthage(origin: CarthageOrigin, requirement: CarthageRequirement, platforms: Set<Platform>)

    private enum Kind: String, Codable {
        case carthage
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case requirement
        case platforms
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .carthage:
            let origin = try container.decode(CarthageOrigin.self, forKey: .origin)
            let requirement = try container.decode(CarthageRequirement.self, forKey: .requirement)
            let platforms = try container.decode(Set<Platform>.self, forKey: .platforms)
            self = .carthage(origin: origin, requirement: requirement, platforms: platforms)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .carthage(origin, requirement, platforms):
            try container.encode(Kind.carthage, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(requirement, forKey: .requirement)
            try container.encode(platforms, forKey: .platforms)
        }
    }
    
    // MARK: - Carthage Origin
    
    public enum CarthageOrigin: Codable, Equatable {
        case github(path: String)
        case git(path: String)
        case binary(path: String)
        
        private enum Kind: String, Codable {
            case github
            case git
            case binary
        }
        
        private enum CodingKeys: String, CodingKey {
            case kind
            case path
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .github:
                let path = try container.decode(String.self, forKey: .path)
                self = .github(path: path)
            case .git:
                let path = try container.decode(String.self, forKey: .path)
                self = .git(path: path)
            case .binary:
                let path = try container.decode(String.self, forKey: .path)
                self = .binary(path: path)
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .github(path):
                try container.encode(Kind.github, forKey: .kind)
                try container.encode(path, forKey: .path)
            case let .git(path):
                try container.encode(Kind.git, forKey: .kind)
                try container.encode(path, forKey: .path)
            case let .binary(path):
                try container.encode(Kind.binary, forKey: .kind)
                try container.encode(path, forKey: .path)
            }
        }
    }
    
    // MARK: - Carthage Requirement
    
    public enum CarthageRequirement: Codable, Equatable {
        case exact(Version)
        case upToNext(Version)
        case atLeast(Version)
        case branch(String)
        case revision(String)

        private enum Kind: String, Codable {
            case exact
            case upToNext
            case atLeast
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
            case .upToNext:
                let version = try container.decode(Version.self, forKey: .version)
                self = .upToNext(version)
            case .atLeast:
                let version = try container.decode(Version.self, forKey: .version)
                self = .atLeast(version)
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
            case let .upToNext(version):
                try container.encode(Kind.upToNext, forKey: .kind)
                try container.encode(version, forKey: .version)
            case let .atLeast(version):
                try container.encode(Kind.atLeast, forKey: .kind)
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
