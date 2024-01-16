import Foundation
import TSCBasic

public enum GraphDependency: Hashable, CustomStringConvertible, Comparable, Codable {
    public struct XCFramework: Hashable, CustomStringConvertible, Comparable, Codable {
        public let path: AbsolutePath
        public let infoPlist: XCFrameworkInfoPlist
        public let primaryBinaryPath: AbsolutePath
        public let linking: BinaryLinking
        public let mergeable: Bool
        public let status: FrameworkStatus
        public let macroPath: AbsolutePath?

        public init(
            path: AbsolutePath,
            infoPlist: XCFrameworkInfoPlist,
            primaryBinaryPath: AbsolutePath,
            linking: BinaryLinking,
            mergeable: Bool,
            status: FrameworkStatus,
            macroPath: AbsolutePath?
        ) {
            self.path = path
            self.infoPlist = infoPlist
            self.primaryBinaryPath = primaryBinaryPath
            self.linking = linking
            self.mergeable = mergeable
            self.status = status
            self.macroPath = macroPath
        }

        public var description: String {
            "xcframework '\(path.basename)'"
        }

        public static func < (lhs: GraphDependency.XCFramework, rhs: GraphDependency.XCFramework) -> Bool {
            lhs.description < rhs.description
        }
    }

    public enum PackageProductType: String, Hashable, CustomStringConvertible, Comparable, Codable {
        public var description: String {
            rawValue
        }

        case runtime = "runtime package product"
        case plugin = "plugin package product"
        case macro = "macro package product"

        public static func < (lhs: PackageProductType, rhs: PackageProductType) -> Bool {
            lhs.description < rhs.description
        }
    }

    case xcframework(GraphDependency.XCFramework)

    /// A dependency that represents a pre-compiled framework.
    case framework(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        status: FrameworkStatus
    )

    /// A dependency that represents a pre-compiled library.
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        swiftModuleMap: AbsolutePath?
    )

    /// A dependency that represents a pre-compiled bundle.
    case bundle(path: AbsolutePath)

    /// A dependency that represents a package product.
    case packageProduct(path: AbsolutePath, product: String, type: PackageProductType)

    /// A dependency that represents a target that is defined in the project at the given path.
    case target(name: String, path: AbsolutePath)

    /// A dependency that represents an SDK
    case sdk(name: String, path: AbsolutePath, status: SDKStatus, source: SDKSource)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .xcframework(xcframework):
            hasher.combine(xcframework)
        case let .framework(path, _, _, _, _, _, _):
            hasher.combine("framework")
            hasher.combine(path)
        case let .library(path, _, _, _, _):
            hasher.combine("library")
            hasher.combine(path)
        case let .bundle(path):
            hasher.combine("bundle")
            hasher.combine(path)
        case let .packageProduct(path, product, isPlugin):
            hasher.combine("package")
            hasher.combine(path)
            hasher.combine(product)
            hasher.combine(isPlugin)
        case let .target(name, path):
            hasher.combine("target")
            hasher.combine(name)
            hasher.combine(path)
        case let .sdk(name, path, status, source):
            hasher.combine("sdk")
            hasher.combine(name)
            hasher.combine(path)
            hasher.combine(status)
            hasher.combine(source)
        }
    }

    public var isTarget: Bool {
        switch self {
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .bundle: return false
        case .packageProduct: return false
        case .target: return true
        case .sdk: return false
        }
    }

    /**
     When the graph dependency represents a pre-compiled static binary.
     */
    public var isStaticPrecompiled: Bool {
        switch self {
        case let .xcframework(xcframework):
            return xcframework.linking == .static
        case let .framework(_, _, _, _, linking, _, _),
             let .library(_, _, linking, _, _): return linking == .static
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    /**
     When the graph dependency represents a dynamic precompiled binary, it returns true.
     */
    public var isDynamicPrecompiled: Bool {
        switch self {
        case let .xcframework(xcframework):
            return xcframework.linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _),
             let .library(_, _, linking, _, _): return linking == .dynamic
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    public var isPrecompiled: Bool {
        switch self {
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .bundle: return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    public var isPrecompiledDynamicAndLinkable: Bool {
        switch self {
        case let .xcframework(xcframework):
            return xcframework.linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _),
             let .library(path: _, publicHeaders: _, linking: linking, architectures: _, swiftModuleMap: _):
            return linking == .dynamic
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    // MARK: - Internal

    public var targetDependency: (name: String, path: AbsolutePath)? {
        switch self {
        case let .target(name: name, path: path):
            return (name, path)
        default:
            return nil
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .xcframework:
            return "xcframework '\(name)'"
        case .framework:
            return "framework '\(name)'"
        case .library:
            return "library '\(name)'"
        case .bundle:
            return "bundle '\(name)'"
        case .packageProduct:
            return "package '\(name)'"
        case .target:
            return "target '\(name)'"
        case .sdk:
            return "sdk '\(name)'"
        }
    }

    public var name: String {
        switch self {
        case let .xcframework(xcframework):
            return xcframework.path.basename
        case let .framework(path, _, _, _, _, _, _):
            return path.basename
        case let .library(path, _, _, _, _):
            return path.basename
        case let .bundle(path):
            return path.basename
        case let .packageProduct(_, product, _):
            return product
        case let .target(name, _):
            return name
        case let .sdk(name, _, _, _):
            return name
        }
    }

    // MARK: - Comparable

    public static func < (lhs: GraphDependency, rhs: GraphDependency) -> Bool {
        lhs.description < rhs.description
    }
}
