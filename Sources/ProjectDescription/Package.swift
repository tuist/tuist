/// A dependency of a Swift package.
///
/// A package dependency can be either:
///     - remote: A Git URL to the source of the package,
///     and a requirement for the version of the package.
///     - local: A relative path to the package.
public enum Package: Equatable, Codable, Sendable {
    case remote(url: String, requirement: Requirement)
    case registry(identifier: String, requirement: Requirement)
    case local(path: Path)

    private enum Kind: String, Codable {
        case remote
        case registry
        case local
    }
}

extension Package {
    public enum Requirement: Codable, Equatable, Sendable {
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
    }
}

extension Package {
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
    public static func package(url: String, from version: Version) -> Package {
        .package(url: url, .upToNextMajor(from: version))
    }

    /// Add a remote package dependency given a version requirement.
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - requirement: A dependency requirement. See static methods on `Package.Requirement` for available options.
    public static func package(url: String, _ requirement: Package.Requirement) -> Package {
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
    public static func package(url: String, _ range: Range<Version>) -> Package {
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
    public static func package(url: String, _ range: ClosedRange<Version>) -> Package {
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
    public static func package(path: Path) -> Package {
        .local(path: path)
    }

    /// Adds a package dependency that uses the version requirement, starting with the given minimum version,
    /// going up to the next major version.
    ///
    /// This is the recommended way to specify a remote package dependency.
    /// It allows you to specify the minimum version you require, allows updates that include bug fixes
    /// and backward-compatible feature updates, but requires you to explicitly update to a new major version of the dependency.
    /// This approach provides the maximum flexibility on which version to use,
    /// while making sure you don't update to a version with breaking changes,
    /// and helps to prevent conflicts in your dependency graph.
    ///
    /// The following example allows the Swift Package Manager to select a version
    /// like a  `1.2.3`, `1.2.4`, or `1.3.0`, but not `2.0.0`.
    ///
    /// ```swift
    /// .package(id: "scope.name", from: "1.2.3"),
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identity of the package.
    ///   - version: The minimum version requirement.
    ///
    /// - Returns: A `Package` instance.
    public static func package(id: String, from version: Version) -> Package {
        .registry(identifier: id, requirement: .upToNextMajor(from: version))
    }

    /// Adds a package dependency that uses the exact version requirement.
    ///
    /// Specifying exact version requirements are not recommended as
    /// they can cause conflicts in your dependency graph when multiple other packages depend on a package.
    /// Because Swift packages follow the semantic versioning convention,
    /// think about specifying a version range instead.
    ///
    /// The following example instructs the Swift Package Manager to use version `1.2.3`.
    ///
    /// ```swift
    /// .package(id: "scope.name", exact: "1.2.3"),
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identity of the package.
    ///   - version: The exact version of the dependency for this requirement.
    ///
    /// - Returns: A `Package` instance.
    public static func package(id: String, exact version: Version) -> Package {
        .registry(identifier: id, requirement: .exact(version))
    }

    /// Adds a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    /// ```swift
    /// .package(id: "scope.name", "1.2.3"..<"1.2.6"),
    /// ```
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions between 1.0.0 and 2.0.0
    ///
    /// ```swift
    /// .package(id: "scope.name", .upToNextMajor(from: "1.0.0")),
    /// ```
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions between 1.0.0 and 1.1.0
    ///
    /// ```swift
    /// .package(id: "scope.name", .upToNextMinor(from: "1.0.0")),
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identity of the package.
    ///   - range: The custom version range requirement.
    ///
    /// - Returns: A `Package` instance.
    public static func package(id: String, _ range: Range<Version>) -> Package {
        .registry(identifier: id, requirement: .range(from: range.lowerBound, to: range.upperBound))
    }

    /// Adds a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift Package Manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    /// ```swift
    /// .package(id: "scope.name", "1.2.3"..."1.2.6"),
    /// ```
    ///
    /// - Parameters:
    ///   - id: The identity of the package.
    ///   - range: The closed version range requirement.
    ///
    /// - Returns: A `Package` instance.
    public static func package(id: String, _ range: ClosedRange<Version>) -> Package {
        // Increase upper-bound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers
        )
        return .registry(identifier: id, requirement: .range(from: range.lowerBound, to: upperBound))
    }
}

// Mark common APIs used by mistake as unavailable to provide better error messages.

extension Package {
    @available(*, unavailable, message: "use package(url:_:) with the .exact(Version) initializer instead")
    public static func package(url _: String, version _: Version) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .branch(String) initializer instead")
    public static func package(url _: String, branch _: String) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) with the .revision(String) initializer instead")
    public static func package(url _: String, revision _: String) -> Package {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:_:) without the range label instead")
    public static func package(url _: String, range _: Range<Version>) -> Package {
        fatalError()
    }
}
