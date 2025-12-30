/// Dependency status used by dependencies
public enum LinkingStatus: String, Codable, Hashable, Sendable {
    /// Required dependency
    case required

    /// Optional dependency (weakly linked)
    case optional

    /// Skip linking
    case none
}

/// Expected signature for XCFramework. Can be used to verify the authenticity of the XCFramework against the actual signature
/// calculated from it.
public enum XCFrameworkSignature: Equatable, Hashable, Codable, Sendable {
    /// The XCFramework is not signed.
    case unsigned

    /// The XCFramework is signed with an Apple Development certificate.
    case signedWithAppleCertificate(teamIdentifier: String, teamName: String)

    /// The XCFramework is signed by a self issued code signing identity.
    case selfSigned(fingerprint: String)
}

@available(*, deprecated, renamed: "LinkingStatus")
typealias FrameworkStatus = LinkingStatus

@available(*, deprecated, renamed: "LinkingStatus")
typealias SDKStatus = LinkingStatus

/// Dependency type used by `.sdk` target dependencies
public enum SDKType: String, Codable, Hashable, Sendable {
    /// Library SDK dependency
    /// Libraries are located in:
    /// `{path-to-xcode}.app/Contents/Developer/Platforms/{platform}.platform/Developer/SDKs/{runtime}.sdk/usr/lib`
    case library

    /// Swift library SDK dependency
    /// Swift libraries are located in:
    /// `{path-to-xcode}.app/Contents/Developer/Platforms/{platform}.platform/Developer/SDKs/{runtime}.sdk/usr/lib/swift`
    case swiftLibrary

    /// Framework SDK dependency
    case framework
}

/// A target dependency.
public enum TargetDependency: Codable, Hashable, Sendable {
    public enum PackageType: Codable, Hashable, Sendable {
        /// A runtime package type represents a standard package whose sources are linked at runtime.
        /// For example importing the framework and consuming from dependent targets.
        case runtime

        /// A runtime embedded package type represents a package that's embedded in the product at runtime.
        case runtimeEmbedded

        /// A plugin package represents a package that's loaded by the build system at compile-time to
        /// extend the compilation process.
        case plugin

        /// A macro package represents a package that contains a Swift Macro.
        case macro
    }

    /// Dependency on another target within the same project
    ///
    /// - Parameters:
    ///   - name: Name of the target to depend on
    ///   - status: The dependency status (optional dependencies are weakly linked)
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case target(name: String, status: LinkingStatus = .required, condition: PlatformCondition? = nil)

    /// Dependency on a macro target within the same project
    ///
    /// - Parameters:
    ///   - name: Name of the target to depend on
    case macro(name: String)

    /// Dependency on a target within another project
    ///
    /// - Parameters:
    ///   - target: Name of the target to depend on
    ///   - path: Relative path to the other project directory
    ///   - status: The dependency status (optional dependencies are weakly linked)
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case project(target: String, path: Path, status: LinkingStatus = .required, condition: PlatformCondition? = nil)

    /// Dependency on a prebuilt framework
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt framework
    ///   - status: The dependency status (optional dependencies are weakly linked)
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case framework(path: Path, status: LinkingStatus = .required, condition: PlatformCondition? = nil)

    /// Dependency on prebuilt library
    ///
    /// - Parameters:
    ///   - path: Relative path to the prebuilt library
    ///   - publicHeaders: Relative path to the library's public headers directory
    ///   - swiftModuleMap: Relative path to the library's swift module map file
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case library(path: Path, publicHeaders: Path, swiftModuleMap: Path?, condition: PlatformCondition? = nil)

    /// Dependency on a swift package manager product using Xcode native integration. It's recommended to use `external` instead.
    /// For more info, check the [external dependencies documentation
    /// ](https://docs.tuist.dev/en/guides/features/projects/dependencies#external-dependencies).
    ///
    /// - Parameters:
    ///   - product: The name of the output product. ${PRODUCT_NAME} inside Xcode.
    ///              e.g. RxSwift
    ///   - type: The type of package being integrated.
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case package(product: String, type: PackageType = .runtime, condition: PlatformCondition? = nil)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (not including extension)
    ///            e.g. `ARKit`, `c++`
    ///   - type: The dependency type
    ///   - status: The dependency status (optional dependencies are weakly linked)
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case sdk(name: String, type: SDKType, status: LinkingStatus, condition: PlatformCondition? = nil)

    /// Dependency on a xcframework
    ///
    /// - Parameters:
    ///   - path: Relative path to the xcframework
    ///   - expectedSignature: The expected signature if the xcframework is signed.
    ///     Used for verifying the xcframework's integrity against the actual fingerprint derived from the given xcframeowrk
    ///   - status: The dependency status (optional dependencies are weakly linked)
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case xcframework(
        path: Path,
        expectedSignature: XCFrameworkSignature? = nil,
        status: LinkingStatus = .required,
        condition: PlatformCondition? = nil
    )

    /// Dependency on XCTest.
    case xctest

    /// Dependency on an external dependency imported through `Package.swift`.
    ///
    /// - Parameters:
    ///   - name: Name of the external dependency
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    case external(name: String, condition: PlatformCondition? = nil)

    /// Dependency on system library or framework
    ///
    /// - Parameters:
    ///   - name: Name of the system library or framework (including extension)
    ///            e.g. `ARKit.framework`, `libc++.tbd`
    ///   - type: Whether or not this dependecy is required. Defaults to `.required`
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    public static func sdk(name: String, type: SDKType, condition: PlatformCondition? = nil) -> TargetDependency {
        .sdk(name: name, type: type, status: .required, condition: condition)
    }

    /// Dependency on another target within the same project. This is just syntactic sugar for `.target(name: target.name)`.
    ///
    /// - Parameters:
    ///   - target: Instance of the target to depend on
    ///   - condition: condition under which to use this dependency, `nil` if this should always be used
    public static func target(_ target: Target, condition: PlatformCondition? = nil) -> TargetDependency {
        .target(name: target.name, condition: condition)
    }

    public var typeName: String {
        switch self {
        case .target:
            return "target"
        case .macro:
            return "macro"
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
