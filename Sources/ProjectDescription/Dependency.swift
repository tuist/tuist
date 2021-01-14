import Foundation

/// Contains the description of external dependency that can by installed using Tuist.
public enum Dependency: Codable, Equatable {
    /// Origin of the Carthage dependency
    public enum CarthageOrigin: Codable, Equatable {
        /// Mimics `github` keyword from `Cartfile`. GitHub repositories (both GitHub.com and GitHub Enterprise).
        case github(path: String)
        /// Mimics `git` keyword from `Cartfile`. Other Git repositories.
        case git(path: String)
        /// Mimics `binary` keyword from `Cartfile`. Dependencies that are only available as compiled binary `.frameworks`.
        case binary(path: String)
    }

    /// Requirement for the Carthage dependency
    public enum CarthageRequirement: Codable, Equatable {
        /// Mimics `== 1.0` from `Cartfile`.
        case exact(Version)
        /// Mimics `~> 1.0` from `Cartfile`.
        case upToNext(Version)
        /// Mimics `>= 1.0` from `Cartfile`.
        case atLeast(Version)
        /// Mimics `"branch"` from `Cartfile`.
        case branch(String)
        /// Mimics `"revision"` from `Cartfile`.
        case revision(String)
    }

    /// Contains the description of dependency that can by installed using Carthage. More: https://github.com/Carthage/Carthage/blob/master/Documentation/Artifacts.md
    case carthage(origin: CarthageOrigin, requirement: CarthageRequirement, platforms: Set<Platform>)
}

// MARK: - Dependency: Codable

extension Dependency {
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
}

// MARK: - Dependency.CarthageRequirement: Codable

extension Dependency.CarthageRequirement {
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

// MARK: - Dependency.CarthageOrigin: Codable

extension Dependency.CarthageOrigin {
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
