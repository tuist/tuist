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

    public enum VersionRequirement: Codable, Equatable {
        case upToNextMajorVersion(String)
        case upToNextMinorVersion(String)
        case range(from: String, to: String)
        case exact(String)
        case branch(String)
        case revision(String)

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
                let version = try container.decode(String.self, forKey: .minimumVersion)
                self = .exact(version)
            } else if kind == "versionRange" {
                let minimumVersion = try container.decode(String.self, forKey: .minimumVersion)
                let maximumVersion = try container.decode(String.self, forKey: .maximumVersion)
                self = .range(from: minimumVersion, to: maximumVersion)
            } else if kind == "upToNextMinorVersion" {
                let version = try container.decode(String.self, forKey: .minimumVersion)
                self = .upToNextMinorVersion(version)
            } else if kind == "upToNextMajorVersion" {
                let version = try container.decode(String.self, forKey: .minimumVersion)
                self = .upToNextMajorVersion(version)
            } else {
                fatalError("XCRemoteSwiftPackageReference kind '\(kind)' not supported")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            switch self {
            case let .upToNextMajorVersion(version):
                try container.encode("upToNextMajorVersion", forKey: .kind)
                try container.encode(version, forKey: .minimumVersion)
            case let .upToNextMinorVersion(version):
                try container.encode("upToNextMinorVersion", forKey: .kind)
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
    
    
    case package(url: String, productName: String, version: VersionRequirement)

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
            self = .package(url: try container.decode(String.self, forKey: .url),
                            productName: try container.decode(String.self, forKey: .productName),
                            version: try container.decode(VersionRequirement.self, forKey: .versionRequirement))
        
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
        case let .package(url, productName, version):
            try container.encode(url, forKey: .url)
            try container.encode(productName, forKey: .productName)
            try container.encode(version, forKey: .versionRequirement)
        case let .sdk(name, status):
            try container.encode(name, forKey: .name)
            try container.encode(status, forKey: .status)
        case let .cocoapods(path):
            try container.encode(path, forKey: .path)
        }
    }
}
