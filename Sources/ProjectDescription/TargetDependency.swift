import Foundation

/// Dependency status used by `.sdk` target dependencies
public enum SDKStatus: String, Codable, Hashable {
    /// Required dependency
    case required

    /// Optional dependency (weakly linked)
    case optional
}

/// Dependency type used by `.sdk` target dependencies
public enum SDKType: String, Codable, Hashable {
    /// Library SDK dependency
    case library

    /// Framework SDK dependency
    case framework
}

/// A target dependency.
public enum TargetDependency: Codable, Hashable {
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

    /// Dependency on a swift package manager product using Xcode native integration. It's recommended to use `external` instead.
    /// For more info, check the [external dependencies documentation](https://docs.tuist.io/guides/third-party-dependencies/).
    ///
    /// - Parameters:
    ///   - product: The name of the output product. ${PRODUCT_NAME} inside Xcode.
    ///              e.g. RxSwift
    case package(product: String)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (not including extension)
    ///            e.g. `ARKit`, `c++`
    ///   - type: The dependency type
    ///   - status: The dependency status (optional dependencies are weakly linked)
    case sdk(name: String, type: SDKType, status: SDKStatus)

    /// Dependency on a xcframework
    ///
    /// - Parameters:
    ///   - path: Relative path to the xcframework
    case xcframework(path: Path)

    /// Dependency on XCTest.
    case xctest

    /// Dependency on an external dependency imported through `Dependencies.swift`.
    case external(name: String)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (including extension)
    ///            e.g. `ARKit.framework`, `libc++.tbd`
    ///
    /// Note: Defaults to using a `required` dependency status
    public static func sdk(name: String, type: SDKType) -> TargetDependency {
        .sdk(name: name, type: type, status: .required)
    }

    /// Dependency on another target within the same project. This is just syntactic sugar for `.target(name: target.name)`.
    ///
    /// - Parameters:
    ///   - target: Instance of the target to depend on
    public static func target(_ target: Target) -> TargetDependency {
        .target(name: target.name)
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
        case .xcframework:
            return "xcframework"
        case .xctest:
            return "xctest"
        case .external:
            return "external"
        }
    }
}
