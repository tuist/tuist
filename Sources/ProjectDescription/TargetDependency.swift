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
    case project(target: String, path: Path)

    /// Dependency on a prebuilt framework
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt framework
    case framework(path: Path)

    /// Dependency on prebuilt library
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt library
    ///   - publicHeaders: Relative path to the library's public headers directory
    ///   - swiftModuleMap: Relative path to the library's swift module map file
    case library(path: Path, publicHeaders: Path, swiftModuleMap: Path?)

    /// Dependency on a swift package manager product. Define packages in the `packages` variable on `Project`
    ///
    /// - Parameters:
    ///   - product: The name of the output product. ${PRODUCT_NAME} inside Xcode.
    ///              e.g. RxSwift
    case package(product: String)

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
    case cocoapods(path: Path)

    /// Dependency on a xcframework
    ///
    /// - Parameters:
    ///   - path: Relative path to the xcframework

    case xcFramework(path: Path)

    /// Dependency on XCTest.
    case xctest

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (including extension)
    ///            e.g. `ARKit.framework`, `libc++.tbd`
    ///
    /// Note: Defaults to using a `required` dependency status
    public static func sdk(name: String) -> TargetDependency {
        .sdk(name: name, status: .required)
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
        case .xcFramework:
            return "xcframework"
        case .xctest:
            return "xctest"
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
                path: try container.decode(Path.self, forKey: .path)
            )

        case "framework":
            self = .framework(path: try container.decode(Path.self, forKey: .path))

        case "xcframework":
            self = .xcFramework(path: try container.decode(Path.self, forKey: .path))

        case "library":
            self = .library(
                path: try container.decode(Path.self, forKey: .path),
                publicHeaders: try container.decode(Path.self, forKey: .publicHeaders),
                swiftModuleMap: try container.decodeIfPresent(Path.self, forKey: .swiftModuleMap)
            )

        case "package":
            let package = try container.decode(String.self, forKey: .package)
            self = .package(product: package)
        case "sdk":
            self = .sdk(name: try container.decode(String.self, forKey: .name),
                        status: try container.decode(SDKStatus.self, forKey: .status))

        case "cocoapods":
            self = .cocoapods(path: try container.decode(Path.self, forKey: .path))

        case "xctest":
            self = .xctest

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
        case let .xcFramework(path):
            try container.encode(path, forKey: .path)
        case .xctest:
            break
        }
    }
}
