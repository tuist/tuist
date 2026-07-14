extension Package {
    /// A Swift package dependency and its enabled traits.
    public struct Dependency: Codable, Equatable, Sendable {
        /// The type of package dependency.
        public enum Kind: Codable, Equatable, Sendable {
            /// A dependency located at a local path.
            case fileSystem(path: Path)
            /// A dependency hosted in a source control repository.
            case sourceControl(location: String, requirement: Package.Requirement)
            /// A dependency published to a package registry.
            case registry(id: String, requirement: Package.Requirement)
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

        /// The corresponding legacy package value.
        public var package: Package {
            switch kind {
            case let .fileSystem(path):
                .local(path: path)
            case let .sourceControl(location, requirement):
                .remote(url: location, requirement: requirement)
            case let .registry(id, requirement):
                .registry(identifier: id, requirement: requirement)
            }
        }

        /// Creates a remote package dependency using a minimum version and enabled traits.
        public static func package(
            url: String,
            from version: Version,
            traits: Set<Trait> = [.defaults]
        ) -> Dependency {
            .package(url: url, .upToNextMajor(from: version), traits: traits)
        }

        /// Creates a remote package dependency using a requirement and enabled traits.
        public static func package(
            url: String,
            _ requirement: Package.Requirement,
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
                .range(from: range.lowerBound, to: range.upperBound),
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
            .init(kind: .registry(id: id, requirement: .upToNextMajor(from: version)), traits: traits)
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
                kind: .registry(id: id, requirement: .range(from: range.lowerBound, to: range.upperBound)),
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
                kind: .registry(id: id, requirement: .range(from: range.lowerBound, to: upperBound)),
                traits: traits
            )
        }
    }
}
