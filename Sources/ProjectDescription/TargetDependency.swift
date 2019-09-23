import Foundation

// MARK: - TargetDependency

/// Dependency status used by `.sdk` target dependencies
public enum SDKStatus: String {
    /// Required dependency
    case required

    /// Optional dependency (weakly linked)
    case optional
}

/// Defines the target dependencies supported by Tuist
public enum TargetDependency: Codable, Equatable {
    public enum PackageType: Equatable, Codable {
        case remote(url: String, productName: String, versionRequirement: VersionRequirement)
        case local(path: String, productName: String)

        private enum Kind: String, Codable {
            case remote
            case local
        }

        enum CodingKeys: String, CodingKey {
            case kind
            case url
            case productName
            case versionRequirement
            case path
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .kind)
            switch kind {
            case .remote:
                let url = try container.decode(String.self, forKey: .url)
                let productName = try container.decode(String.self, forKey: .productName)
                let versionRequirement = try container.decode(VersionRequirement.self, forKey: .versionRequirement)
                self = .remote(url: url, productName: productName, versionRequirement: versionRequirement)
            case .local:
                let path = try container.decode(String.self, forKey: .path)
                let productName = try container.decode(String.self, forKey: .productName)
                self = .local(path: path, productName: productName)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .remote(url, productName, versionRequirement):
                try container.encode(Kind.remote, forKey: .kind)
                try container.encode(url, forKey: .url)
                try container.encode(productName, forKey: .productName)
                try container.encode(versionRequirement, forKey: .versionRequirement)
            case let .local(path, productName):
                try container.encode(Kind.local, forKey: .kind)
                try container.encode(path, forKey: .path)
                try container.encode(productName, forKey: .productName)
            }
        }
    }

    public enum VersionRequirement: Codable, Equatable {
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
                try container.encode("revision", forKey: .revision)
                try container.encode(revision, forKey: .revision)
            }
        }
    }

    /// Dependency on another target within the same project
    ///
    /// - Parameters:
    ///   - name: Name of the target to depend on
    case target(name: String)

    /// Dependency on a target within another project
    ///
    /// - Parameters:
    ///   - target: Name of the target to depend on
    ///   - path: Relative path to the other project directory
    case project(target: String, path: String)

    /// Dependency on a prebuilt framework
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt framework
    case framework(path: String)

    /// Dependency on prebuilt library
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt library
    ///   - publicHeaders: Relative path to the library's public headers directory
    ///   - swiftModuleMap: Relative path to the library's swift module map file
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)

    case package(PackageType)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (including extension)
    ///            e.g. `ARKit.framework`, `libc++.tbd`
    ///   - status: The dependency status (optional dependencies are weakly linked)
    case sdk(name: String, status: SDKStatus)

    /// Dependency on CocoaPods pods.
    ///
    /// - Parameters:
    ///     - path: Path to the directory that contains the Podfile.
    case cocoapods(path: String)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (including extension)
    ///            e.g. `ARKit.framework`, `libc++.tbd`
    ///
    /// Note: Defaults to using a `required` dependency status
    public static func sdk(name: String) -> TargetDependency {
        return .sdk(name: name, status: .required)
    }

    public var typeName: String {
        switch self {
        case .target:
            return "target"
        case .project:
            return "project"
        case .framework:
            return "framework"
        case .library:
            return "library"
        case .package:
            return "package"
        case .sdk:
            return "sdk"
        case .cocoapods:
            return "cocoapods"
        }
    }
}

// MARK: - SDKStatus (Coding)

extension SDKStatus: Codable {}

// MARK: - TargetDependency (Coding)

extension TargetDependency {
    public enum CodingError: Error {
        case unknownType(String)
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case name
        case target
        case path
        case url
        case productName
        case versionRequirement = "version_requirement"
        case publicHeaders = "public_headers"
        case swiftModuleMap = "swift_module_map"
        case status
        case package
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "target":
            self = .target(name: try container.decode(String.self, forKey: .name))

        case "project":
            self = .project(
                target: try container.decode(String.self, forKey: .target),
                path: try container.decode(String.self, forKey: .path)
            )

        case "framework":
            self = .framework(path: try container.decode(String.self, forKey: .path))

        case "library":
            self = .library(
                path: try container.decode(String.self, forKey: .path),
                publicHeaders: try container.decode(String.self, forKey: .publicHeaders),
                swiftModuleMap: try container.decodeIfPresent(String.self, forKey: .swiftModuleMap)
            )

        case "package":
            let package = try container.decode(PackageType.self, forKey: .package)
            self = .package(package)
        case "sdk":
            self = .sdk(name: try container.decode(String.self, forKey: .name),
                        status: try container.decode(SDKStatus.self, forKey: .status))

        case "cocoapods":
            self = .cocoapods(path: try container.decode(String.self, forKey: .path))

        default:
            throw CodingError.unknownType(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(typeName, forKey: .type)

        switch self {
        case let .target(name: name):
            try container.encode(name, forKey: .name)
        case let .project(target: target, path: path):
            try container.encode(target, forKey: .target)
            try container.encode(path, forKey: .path)
        case let .framework(path: path):
            try container.encode(path, forKey: .path)
        case let .library(path: path, publicHeaders: publicHeaders, swiftModuleMap: swiftModuleMap):
            try container.encode(path, forKey: .path)
            try container.encode(publicHeaders, forKey: .publicHeaders)
            try container.encodeIfPresent(swiftModuleMap, forKey: .swiftModuleMap)
        case let .package(packageType):
            try container.encode(packageType, forKey: .package)
        case let .sdk(name, status):
            try container.encode(name, forKey: .name)
            try container.encode(status, forKey: .status)
        case let .cocoapods(path):
            try container.encode(path, forKey: .path)
        }
    }
}

extension TargetDependency {
    /// Dependency on remote package
    ///
    /// - Parameters:
    ///     - url: URL poiting to the repository
    ///     - productName: Name of product
    ///     - version: `VersionRequirement` describing which version to resolve
    public static func package(
        url: String,
        productName: String,
        _ version: VersionRequirement
    ) -> TargetDependency {
        return .package(.remote(url: url, productName: productName, versionRequirement: version))
    }

    /// Dependency on local package
    ///
    /// - Parameters:
    ///     - path: Path to the directory that contains local package
    ///     - productName: Name of product
    public static func package(
        path: String,
        productName: String
    ) -> TargetDependency {
        return .package(.local(path: path, productName: productName))
    }

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
    ///    .package(url: "https://example.com/example-package.git", productName: "Example", from: "1.2.3"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - version: The minimum version requirement.
    public static func package(
        url: String,
        productName: String,
        from version: Version
    ) -> TargetDependency {
        return .package(url: url, productName: productName, .upToNextMajor(from: version))
    }

    /// Add a package dependency starting with a specific minimum version, up to
    /// but not including a specified maximum version.
    ///
    /// The following example allows the Swift package manager to pick
    /// versions `1.2.3`, `1.2.4`, `1.2.5`, but not `1.2.6`.
    ///
    ///     .package(url: "https://example.com/example-package.git", productName: "Example", "1.2.3"..<"1.2.6"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The custom version range requirement.
    public static func package(
        url: String,
        productName: String,
        _ range: Range<Version>
    ) -> TargetDependency {
        return .package(url: url, productName: productName, .range(from: range.lowerBound, to: range.upperBound))
    }

    /// Add a package dependency starting with a specific minimum version, going
    /// up to and including a specific maximum version.
    ///
    /// The following example allows the Swift package manager to pick
    /// versions 1.2.3, 1.2.4, 1.2.5, as well as 1.2.6.
    ///
    ///     .package(url: "https://example.com/example-package.git", productName: "Example", "1.2.3"..."1.2.6"),
    ///
    /// - Parameters:
    ///     - url: The valid Git URL of the package.
    ///     - range: The closed version range requirement.
    public static func package(
        url: String,
        productName: String,
        _ range: ClosedRange<Version>
    ) -> TargetDependency {
        // Increase upperbound's patch version by one.
        let upper = range.upperBound
        let upperBound = Version(
            upper.major, upper.minor, upper.patch + 1,
            prereleaseIdentifiers: upper.prereleaseIdentifiers,
            buildMetadataIdentifiers: upper.buildMetadataIdentifiers
        )
        return .package(url: url, productName: productName, range.lowerBound ..< upperBound)
    }

    @available(*, unavailable, message: "use package(url:productName:version:) instead. You must specify a product name.")
    public static func package(url _: String, _: VersionRequirement) -> TargetDependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:productName:_:) instead. You must specify a product name.")
    public static func package(url _: String, _: ClosedRange<Version>) -> TargetDependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:productName:_:) instead. You must specify a product name.")
    public static func package(url _: String, _: Range<Version>) -> TargetDependency {
        fatalError()
    }

    //swiftlint:disable:next line_length
    @available(*, unavailable, message: "use package(url:productName:_:) with the .exact(Version) initializer instead. You must specify a product name")
    public static func package(url _: String, version _: Version) -> TargetDependency {
        fatalError()
    }

    //swiftlint:disable:next line_length
    @available(*, unavailable, message: "use package(url:productName:_:) with the .branch(String) initializer instead. You must specify a product name")
    public static func package(url _: String, branch _: String) -> TargetDependency {
        fatalError()
    }

    //swiftlint:disable:next line_length
    @available(*, unavailable, message: "use package(url:productName:_:) with the .revision(String) initializer instead. You must specify a product name")
    public static func package(url _: String, revision _: String) -> TargetDependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:productName:_:) instead. You must omit `range` and specify a product name.")
    public static func package(url _: String, range _: ClosedRange<Version>) -> TargetDependency {
        fatalError()
    }

    @available(*, unavailable, message: "use package(url:productName:_:) instead. You must omit `range` and specify a product name.")
    public static func package(url _: String, range _: Range<Version>) -> TargetDependency {
        fatalError()
    }
}
