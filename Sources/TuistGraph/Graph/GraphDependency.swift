import Foundation
import TSCBasic

public enum GraphDependency: Hashable, CustomStringConvertible, Comparable, Codable {
    /// A dependency that represents a pre-compiled .xcframework.
    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        linking: BinaryLinking
    )

    /// A dependency that represents a pre-compiled framework.
    case framework(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        isCarthage: Bool
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
    case packageProduct(path: AbsolutePath, product: String)

    /// A dependency that represents a target that is defined in the project at the given path.
    case target(name: String, path: AbsolutePath)

    /// A dependency that represents an SDK
    case sdk(name: String, path: AbsolutePath, status: SDKStatus, source: SDKSource)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .xcframework(path, _, _, _):
            hasher.combine("xcframework")
            hasher.combine(path)
        case let .framework(path, _, _, _, _, _, _):
            hasher.combine("framework")
            hasher.combine(path)
        case let .library(path, _, _, _, _):
            hasher.combine("library")
            hasher.combine(path)
        case let .bundle(path):
            hasher.combine("bundle")
            hasher.combine(path)
        case let .packageProduct(path, product):
            hasher.combine("package")
            hasher.combine(path)
            hasher.combine(product)
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
        case let .xcframework(path, _, _, _):
            return "xcframework '\(path.basename)'"
        case let .framework(path, _, _, _, _, _, _):
            return "framework '\(path.basename)'"
        case let .library(path, _, _, _, _):
            return "library '\(path.basename)'"
        case let .bundle(path):
            return "bundle '\(path.basename)'"
        case let .packageProduct(_, product):
            return "package '\(product)'"
        case let .target(name, _):
            return "target '\(name)'"
        case let .sdk(name, _, _, _):
            return "sdk '\(name)'"
        }
    }

    // MARK: - Comparable

    public static func < (lhs: GraphDependency, rhs: GraphDependency) -> Bool {
        lhs.description < rhs.description
    }
}
