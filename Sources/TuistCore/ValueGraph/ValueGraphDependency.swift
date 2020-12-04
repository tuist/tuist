import Foundation
import TSCBasic

public enum ValueGraphDependency: Hashable {
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

    /// A dependency that represents a package product.
    case packageProduct(path: AbsolutePath, product: String)

    /// A dependency that represents a target that is defined in the project at the given path.
    case target(name: String, path: AbsolutePath)

    /// A dependency that represents an SDK
    case sdk(name: String, path: AbsolutePath, status: SDKStatus, source: SDKSource)

    /// A dependency that represents a pod installlation.
    case cocoapods(path: AbsolutePath)

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
        case let .cocoapods(path):
            hasher.combine("pods")
            hasher.combine(path)
        }
    }

    public var isTarget: Bool {
        switch self {
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .packageProduct: return false
        case .target: return true
        case .sdk: return false
        case .cocoapods: return false
        }
    }

    public var isPrecompiled: Bool {
        switch self {
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        case .cocoapods: return false
        }
    }
}
