/// A Swift package dependency and its optional trait selection.
///
/// When `traits` is `nil`, the package uses its default traits. An empty array disables all default traits.
public struct PackageConfiguration: Codable, Equatable, Sendable {
    /// The package dependency.
    public let package: Package

    /// The selected traits. An empty array disables the package's default traits.
    public let traits: [String]?

    public init(package: Package, traits: [String]? = nil) {
        self.package = package
        self.traits = traits
    }

    /// Creates a remote package dependency using a minimum version and optional traits.
    public static func package(url: String, from version: Version, traits: [String]? = nil) -> PackageConfiguration {
        .init(package: Package.package(url: url, from: version), traits: traits)
    }

    /// Creates a remote package dependency using a requirement and optional traits.
    public static func package(
        url: String,
        _ requirement: Package.Requirement,
        traits: [String]? = nil
    ) -> PackageConfiguration {
        .init(package: Package.package(url: url, requirement), traits: traits)
    }

    /// Creates a remote package dependency using a version range and optional traits.
    public static func package(
        url: String,
        _ range: Range<Version>,
        traits: [String]? = nil
    ) -> PackageConfiguration {
        .init(package: Package.package(url: url, range), traits: traits)
    }

    /// Creates a remote package dependency using a closed version range and optional traits.
    public static func package(
        url: String,
        _ range: ClosedRange<Version>,
        traits: [String]? = nil
    ) -> PackageConfiguration {
        .init(package: Package.package(url: url, range), traits: traits)
    }

    /// Creates a local package dependency with optional traits.
    public static func package(path: Path, traits: [String]? = nil) -> PackageConfiguration {
        .init(package: Package.package(path: path), traits: traits)
    }

    /// Creates a registry package dependency using a minimum version and optional traits.
    public static func package(id: String, from version: Version, traits: [String]? = nil) -> PackageConfiguration {
        .init(package: Package.package(id: id, from: version), traits: traits)
    }

    /// Creates a registry package dependency using an exact version and optional traits.
    public static func package(id: String, exact version: Version, traits: [String]? = nil) -> PackageConfiguration {
        .init(package: Package.package(id: id, exact: version), traits: traits)
    }

    /// Creates a registry package dependency using a version range and optional traits.
    public static func package(
        id: String,
        _ range: Range<Version>,
        traits: [String]? = nil
    ) -> PackageConfiguration {
        .init(package: Package.package(id: id, range), traits: traits)
    }

    /// Creates a registry package dependency using a closed version range and optional traits.
    public static func package(
        id: String,
        _ range: ClosedRange<Version>,
        traits: [String]? = nil
    ) -> PackageConfiguration {
        .init(package: Package.package(id: id, range), traits: traits)
    }
}
