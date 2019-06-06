import Foundation

// MARK: - TargetDependency

public enum TargetDependency: Codable {
    public enum VersionRules: Codable, Equatable {
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

    case target(name: String)
    case project(target: String, path: String)
    case framework(path: String)
    case library(path: String, publicHeaders: String, swiftModuleMap: String?)
    case package(url: String, productName: String, version: VersionRules)

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
        }
    }
}

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
        case versionRules = "version_rules"
        case publicHeaders = "public_headers"
        case swiftModuleMap = "swift_module_map"
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
                            version: try container.decode(VersionRules.self, forKey: .versionRules))

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
            try container.encode(version, forKey: .versionRules)
        }
    }
}
