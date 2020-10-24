/// A dependency of a Swift package.
///
/// A package dependency can be either:
///     - remote: A Git URL to the source of the package,
///     and a requirement for the version of the package.
///     - local: A relative path to the package.
public enum Package: Equatable, Codable {
    case remote(url: String, requirement: Requirement)
    case local(path: Path)

    private enum Kind: String, Codable {
        case remote
        case local
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case url
        case productName
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
            let path = try container.decode(Path.self, forKey: .path)
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

public extension Package {
    enum Requirement: Codable, Equatable {
        case upToNextMajor(from: Version)
        case upToNextMinor(from: Version)
        case range(from: Version, to: Version)
        case exact(Version)
        case branch(String)
        case revision(String)

        @available(*, unavailable, message: "use upToNextMajor(from:) instead.")
        static func upToNextMajor(_: Version) {
            fatalError()
        }

        @available(*, unavailable, message: "use upToNextMinor(from:) instead.")
        static func upToNextMinor(_: Version) {
            fatalError()
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case revision
            case branch
            case minimumVersion
            case maximumVersion
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind: String = try container.decode(String.self, forKey: .kind)
            if kind == "revision" {
                let revision = try container.decode(String.self, forKey: .revision)
                self = .revision(revision)
            } else if kind == "branch" {
                let branch = try container.decode(String.self, forKey: .branch)
                self = .branch(branch)
            } else if kind == "exactVersion" {
                let version = try container.decode(Version.self, forKey: .minimumVersion)
                self = .exact(version)
            } else if kind == "versionRange" {
                let minimumVersion = try container.decode(Version.self, forKey: .minimumVersion)
                let maximumVersion = try container.decode(Version.self, forKey: .maximumVersion)
                self = .range(from: minimumVersion, to: maximumVersion)
            } else if kind == "upToNextMinor" {
                let version = try container.decode(Version.self, forKey: .minimumVersion)
                self = .upToNextMinor(from: version)
            } else if kind == "upToNextMajor" {
                let version = try container.decode(Version.self, forKey: .minimumVersion)
                self = .upToNextMajor(from: version)
            } else {
                fatalError("XCRemoteSwiftPackageReference kind '\(kind)' not supported")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .upToNextMajor(version):
                try container.encode("upToNextMajor", forKey: .kind)
                try container.encode(version, forKey: .minimumVersion)
            case let .upToNextMinor(version):
                try container.encode("upToNextMinor", forKey: .kind)
                try container.encode(version, forKey: .minimumVersion)
            case let .range(from, to):
                try container.encode("versionRange", forKey: .kind)
                try container.encode(from, forKey: .minimumVersion)
                try container.encode(to, forKey: .maximumVersion)
            case let .exact(version):
                try container.encode("exactVersion", forKey: .kind)
                try container.encode(version, forKey: .minimumVersion)
            case let .branch(branch):
                try container.encode("branch", forKey: .kind)
                try container.encode(branch, forKey: .branch)
            case let .revision(revision):
                try container.encode("revision", forKey: .kind)
                try container.encode(revision, forKey: .revision)
            }
        }
    }
}

public extension Package {
    /// Create a package dependency that uses the version requirement, starting with the given minimum version,
    /// going up to the next major version.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example allows the Swift package manager to select a version
    /// like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.
    ///
    ///    .package(url: "https://example.com/example-package.git", from: "1.2.3"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    static func package(url: String, from version: Version) -> Package {
        .package(url: url, .upToNextMajor(from: version))
    }

    /// Add a remote package dependency given a version requirement.
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Dependency.Requirement` for available options.
    static func package(url: String, _ requirement: Package.Requirement) -> Package {
        .remote(url: url, requirement: requirement)
    }

    /// Add a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift package manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The custom version range requirement.
    static func package(url: String, _ range: Range<Version>) -> Package {
        .remote(url: url, requirement: .range(from: range.lowerBound, to: range.upperBound))
    }

    /// Add a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift package manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(url: "https://example.com/example-package.git", "1.2.3"..."1.2.6"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The closed version range requirement.
    static func package(url: String, _ range: ClosedRange<Version>) -> Package {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers
        )
        return .package(url: url, range.lowerBound ..< upperBound)
    }

    /// Add a dependency to a local package on the filesystem.
    ///
    /// The Swift Package Manager uses the package dependency as-is
    /// and does not perform any source control access. Local package dependencies
    /// are especially useful during development of a new package or when working
    /// on multiple tightly coupled packages.
    ///
    /// - Parameter path: The path of the package.
    static func package(path: Path) -> Package {
        .local(path: path)
    }
}

// Mark common APIs used by mistake as unavailable to provide better error messages.
public extension Package {
    @available(*, unavailable, message: "use package(url:_:) with the .exact(Version) initializer instead")
    static func package(url _: String, version _: Version) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .branch(String) initializer instead")
    static func package(url _: String, branch _: String) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .revision(String) initializer instead")
    static func package(url _: String, revision _: String) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) without the range label instead")
    static func package(url _: String, range _: Range<Version>) -> Package {
        fatalError()
    }
}
