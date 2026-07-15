extension Package {
    /// A Swift package dependency and its enabled traits.
    public struct Dependency: Codable, Equatable, Sendable {
        /// The type of package dependency.
        public enum Kind: Codable, Equatable, Sendable {
            /// A dependency located at a local path.
            case fileSystem(path: Path)
            /// A dependency hosted in a source control repository.
            case sourceControl(location: String, requirement: SourceControlRequirement)
            /// A dependency published to a package registry.
            case registry(id: String, requirement: RegistryRequirement)
        }

        /// A source control package requirement.
        public enum SourceControlRequirement: Codable, Equatable, Sendable {
            /// An exact version requirement.
            case exact(Version)
            /// A version range requirement.
            case range(Range<Version>)
            /// A source control revision requirement.
            case revision(String)
            /// A source control branch requirement.
            case branch(String)
        }

        /// A registry package requirement.
        public enum RegistryRequirement: Codable, Equatable, Sendable {
            /// An exact version requirement.
            case exact(Version)
            /// A version range requirement.
            case range(Range<Version>)
        }

        /// An enabled trait of a dependency.
        public struct Trait: Codable, Hashable, Sendable, ExpressibleByStringLiteral {
            /// Enables all default traits of the dependency.
            public static let defaults = Self(name: "default")

            /// The name of the enabled trait.
            public let name: String

            /// Creates an enabled dependency trait.
            public init(name: String) {
                self.name = name
            }

            /// Creates an enabled dependency trait from its name.
            public init(stringLiteral value: StringLiteralType) {
                self.init(name: value)
            }
        }

        /// The type and location of the dependency.
        public let kind: Kind

        /// The enabled traits. An empty set disables all default traits.
        public let traits: Set<Trait>

        /// Creates a package dependency from its kind and enabled traits.
        public init(kind: Kind, traits: Set<Trait> = [.defaults]) {
            self.kind = kind
            self.traits = traits
        }

        init?(legacyPackage: Package) {
            traits = [.defaults]
            switch legacyPackage {
            case let .local(path):
                kind = .fileSystem(path: path)
            case let .remote(url, requirement):
                kind = .sourceControl(
                    location: url,
                    requirement: SourceControlRequirement(packageRequirement: requirement)
                )
            case let .registry(identifier, requirement):
                guard let requirement = RegistryRequirement(packageRequirement: requirement) else {
                    return nil
                }
                kind = .registry(id: identifier, requirement: requirement)
            }
        }

        /// The corresponding legacy package value.
        public var package: Package {
            switch kind {
            case let .fileSystem(path):
                .local(path: path)
            case let .sourceControl(location, requirement):
                .remote(url: location, requirement: requirement.packageRequirement)
            case let .registry(id, requirement):
                .registry(identifier: id, requirement: requirement.packageRequirement)
            }
        }

        /// Creates a remote package dependency using a minimum version and enabled traits.
        public static func package(
            url: String,
            from version: Version,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .package(
                url: url,
                .range(version ..< Version(version.major + 1, 0, 0)),
                traits: traits
            )
        }

        /// Creates a remote package dependency using a requirement and enabled traits.
        public static func package(
            url: String,
            _ requirement: SourceControlRequirement,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .init(kind: .sourceControl(location: url, requirement: requirement), traits: traits)
        }

        /// Creates a remote package dependency using a version range and enabled traits.
        public static func package(
            url: String,
            _ range: Range<Version>,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .package(
                url: url,
                .range(range),
                traits: traits
            )
        }

        /// Creates a remote package dependency using a closed version range and enabled traits.
        public static func package(
            url: String,
            _ range: ClosedRange<Version>,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            let upper = range.upperBound
            let upperBound = Version(
                upper.major,
                upper.minor,
                upper.patch + 1,
                prereleaseIdentifiers: upper.prereleaseIdentifiers,
                buildMetadataIdentifiers: upper.buildMetadataIdentifiers
            )
            return .package(url: url, range.lowerBound ..< upperBound, traits: traits)
        }

        /// Creates a local package dependency with enabled traits.
        public static func package(
            path: Path,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .init(kind: .fileSystem(path: path), traits: traits)
        }

        /// Creates a registry package dependency using a minimum version and enabled traits.
        public static func package(
            id: String,
            from version: Version,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .init(
                kind: .registry(
                    id: id,
                    requirement: .range(version ..< Version(version.major + 1, 0, 0))
                ),
                traits: traits
            )
        }

        /// Creates a registry package dependency using an exact version and enabled traits.
        public static func package(
            id: String,
            exact version: Version,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .init(kind: .registry(id: id, requirement: .exact(version)), traits: traits)
        }

        /// Creates a registry package dependency using a version range and enabled traits.
        public static func package(
            id: String,
            _ range: Range<Version>,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .init(
                kind: .registry(id: id, requirement: .range(range)),
                traits: traits
            )
        }

        /// Creates a registry package dependency using a closed version range and enabled traits.
        public static func package(
            id: String,
            _ range: ClosedRange<Version>,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            let upper = range.upperBound
            let upperBound = Version(
                upper.major,
                upper.minor,
                upper.patch + 1,
                prereleaseIdentifiers: upper.prereleaseIdentifiers,
                buildMetadataIdentifiers: upper.buildMetadataIdentifiers
            )
            return .init(
                kind: .registry(id: id, requirement: .range(range.lowerBound ..< upperBound)),
                traits: traits
            )
        }
    }
}

extension Package.Dependency.SourceControlRequirement {
    fileprivate init(packageRequirement: Package.Requirement) {
        switch packageRequirement {
        case let .upToNextMajor(version):
            self = .range(version ..< Version(version.major + 1, 0, 0))
        case let .upToNextMinor(version):
            self = .range(version ..< Version(version.major, version.minor + 1, 0))
        case let .range(from, to):
            self = .range(from ..< to)
        case let .exact(version):
            self = .exact(version)
        case let .branch(branch):
            self = .branch(branch)
        case let .revision(revision):
            self = .revision(revision)
        }
    }

    fileprivate var packageRequirement: Package.Requirement {
        switch self {
        case let .exact(version):
            .exact(version)
        case let .range(range):
            .range(from: range.lowerBound, to: range.upperBound)
        case let .revision(revision):
            .revision(revision)
        case let .branch(branch):
            .branch(branch)
        }
    }
}

extension Package.Dependency.RegistryRequirement {
    fileprivate init?(packageRequirement: Package.Requirement) {
        switch packageRequirement {
        case let .upToNextMajor(version):
            self = .range(version ..< Version(version.major + 1, 0, 0))
        case let .upToNextMinor(version):
            self = .range(version ..< Version(version.major, version.minor + 1, 0))
        case let .range(from, to):
            self = .range(from ..< to)
        case let .exact(version):
            self = .exact(version)
        case .branch, .revision:
            return nil
        }
    }

    fileprivate var packageRequirement: Package.Requirement {
        switch self {
        case let .exact(version):
            .exact(version)
        case let .range(range):
            .range(from: range.lowerBound, to: range.upperBound)
        }
    }
}
