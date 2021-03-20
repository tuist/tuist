import Foundation
import TSCBasic
import TuistGraph

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        binaryPath: AbsolutePath
    )
    case library(
        path: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product
    )
    case framework(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        isCarthage: Bool,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product
    )
    case product(target: String, productName: String)
    case sdk(path: AbsolutePath, status: SDKStatus, source: SDKSource)

    init(_ dependency: ValueGraphDependency) {
        switch dependency {
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, isCarthage):
            self = .framework(
                path: path,
                binaryPath: binaryPath,
                isCarthage: isCarthage,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticFramework : .framework
            )
        case let .library(path, _, linking, architectures, _):
            self = .library(
                path: path,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticLibrary : .dynamicLibrary
            )
        case let .xcframework(path, infoPlist, primaryBinaryPath, _):
            self = .xcframework(
                path: path,
                infoPlist: infoPlist,
                primaryBinaryPath: primaryBinaryPath,
                binaryPath: primaryBinaryPath
            )
        default:
            preconditionFailure("unsupported dependencies")
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .library(path, _, _, _):
            hasher.combine(path)
        case let .framework(path, _, _, _, _, _, _, _):
            hasher.combine(path)
        case let .xcframework(path, _, _, _):
            hasher.combine(path)
        case let .product(target, productName):
            hasher.combine(target)
            hasher.combine(productName)
        case let .sdk(path, status, source):
            hasher.combine(path)
            hasher.combine(status)
            hasher.combine(source)
        }
    }

    /// For dependencies that exists in the file system (precompiled frameworks & libraries),
    /// this attribute returns the path to them.
    public var precompiledPath: AbsolutePath? {
        switch self {
        case let .framework(path, _, _, _, _, _, _, _):
            return path
        case let .library(path, _, _, _):
            return path
        case let .xcframework(path, _, _, _):
            return path
        default:
            return nil
        }
    }

    public static func < (lhs: GraphDependencyReference, rhs: GraphDependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.framework(lhsPath, _, _, _, _, _, _, _), .framework(rhsPath, _, _, _, _, _, _, _)):
            return lhsPath < rhsPath
        case let (.xcframework(lhsPath, _, _, _), .xcframework(rhsPath, _, _, _)):
            return lhsPath < rhsPath
        case let (.library(lhsPath, _, _, _), .library(rhsPath, _, _, _)):
            return lhsPath < rhsPath
        case let (.product(lhsTarget, lhsProductName), .product(rhsTarget, rhsProductName)):
            if lhsTarget == rhsTarget {
                return lhsProductName < rhsProductName
            }
            return lhsTarget < rhsTarget
        case let (.sdk(lhsPath, _, _), .sdk(rhsPath, _, _)):
            return lhsPath < rhsPath
        case (.sdk, .framework):
            return true
        case (.sdk, .xcframework):
            return true
        case (.sdk, .product):
            return true
        case (.sdk, .library):
            return true
        case (.product, .framework):
            return true
        case (.product, .xcframework):
            return true
        case (.product, .library):
            return true
        case (.library, .framework):
            return true
        case (.library, .xcframework):
            return true
        case (.framework, .xcframework):
            return true
        default:
            return false
        }
    }
}
