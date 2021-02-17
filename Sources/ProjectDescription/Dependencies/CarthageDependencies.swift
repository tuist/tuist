import Foundation

/// Contains the description of dependency that can by installed using Carthage.
public struct CarthageDependencies: Codable, Equatable {
    /// List of depedencies that can by installed using Carthage.
    public let dependencies: [Dependency]
    /// Set of options that allows to adjust Carthage installation.
    public let options: Options
    
    /// Initializes a new `CarthageDependencies` instance.
    /// - Parameters:
    ///   - dependencies: List of depedencies that can by installed using Carthage.
    ///   - options: Set of options that allows to adjust Carthage installation.
    public init(dependencies: [Dependency], options: Options = .default) {
        self.dependencies = dependencies
        self.options = options
    }
}

public extension CarthageDependencies {
    /// Specifies origin of Carthage dependency.
    enum Dependency: Codable, Equatable {
        case github(path: String, requirement: Requirement)
        case git(path: String, requirement: Requirement)
        case binary(path: String, requirement: Requirement)
    }
    
    /// Specifices version requirement for Carthage depedency.
    enum Requirement: Codable, Equatable {
        case exact(Version)
        case upToNext(Version)
        case atLeast(Version)
        case branch(String)
        case revision(String)
    }
    
    /// Contains set of options that allows to adjust the Carthage installation.
    struct Options: Codable, Equatable {
        /// List of platforms for which you want to install depedencies.
        public let platforms: Set<Platform>
        /// Indicates whether the Carthage produces XCFrameworks or regular frameworks.
        public let useXCFrameworks: Bool
        
        /// Default options.
        public static var `default`: Self {
            .init(
                platforms: .init(Platform.allCases),
                useXCFrameworks: false
            )
        }
        
        /// Initializes a new `CarthageDependencies.Options` instance.
        /// - Parameters:
        ///   - platforms: List of platforms for which you want to install depedencies.
        ///   - useXCFrameworks: Indicates whether the Carthage produces XCFrameworks or regular frameworks.
        public init(platforms: Set<Platform>, useXCFrameworks: Bool) {
            self.platforms = platforms
            self.useXCFrameworks = useXCFrameworks
        }
    }
}

// MARK: - CarthageDependencies.Dependency: Codable

extension CarthageDependencies.Dependency {
    private enum Kind: String, Codable {
        case github
        case git
        case binary
    }
    
    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case requirement
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .github:
            let path = try container.decode(String.self, forKey: .path)
            let requirement = try container.decode(CarthageDependencies.Requirement.self, forKey: .requirement)
            self = .github(path: path, requirement: requirement)
        case .git:
            let path = try container.decode(String.self, forKey: .path)
            let requirement = try container.decode(CarthageDependencies.Requirement.self, forKey: .requirement)
            self = .git(path: path, requirement: requirement)
        case .binary:
            let path = try container.decode(String.self, forKey: .path)
            let requirement = try container.decode(CarthageDependencies.Requirement.self, forKey: .requirement)
            self = .binary(path: path, requirement: requirement)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .github(path, requirement):
            try container.encode(Kind.github, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(requirement, forKey: .requirement)
        case let .git(path, requirement):
            try container.encode(Kind.git, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(requirement, forKey: .requirement)
        case let .binary(path, requirement):
            try container.encode(Kind.binary, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(requirement, forKey: .requirement)
        }
    }
}

// MARK: - CarthageDependencies.Requirement: Codoable

extension CarthageDependencies.Requirement {
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
