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
    case bundle(path: AbsolutePath)
    case product(target: String, productName: String, platformFilter: BuildFilePlatformFilter? = nil)
    case sdk(path: AbsolutePath, status: SDKStatus, source: SDKSource)

    init(_ dependency: GraphDependency) {
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
        Synthesized(dependencyReference: self).hash(into: &hasher)
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
        Synthesized(dependencyReference: lhs) < Synthesized(dependencyReference: rhs)
    }

    // Private helper type to auto-synthesize the hashable & comparable implementations
    // where only the required subset of properties are used.
    private enum Synthesized: Comparable, Hashable {
        case sdk(path: AbsolutePath)
        case product(target: String, productName: String)
        case productWithPlatformFilter(target: String, productName: String, platformFilter: BuildFilePlatformFilter)
        case library(path: AbsolutePath)
        case framework(path: AbsolutePath)
        case xcframework(path: AbsolutePath)
        case bundle(path: AbsolutePath)

        init(dependencyReference: GraphDependencyReference) {
            switch dependencyReference {
            case .xcframework(path: let path, infoPlist: _, primaryBinaryPath: _, binaryPath: _):
                self = .xcframework(path: path)
            case .library(path: let path, linking: _, architectures: _, product: _):
                self = .library(path: path)
            case .framework(
                path: let path,
                binaryPath: _,
                isCarthage: _,
                dsymPath: _,
                bcsymbolmapPaths: _,
                linking: _,
                architectures: _,
                product: _
            ):
                self = .framework(path: path)
            case let .bundle(path: path):
                self = .bundle(path: path)
            case let .product(target: target, productName: productName, platformFilter: platformFilter):
                if let platformFilter = platformFilter {
                    self = .productWithPlatformFilter(target: target, productName: productName, platformFilter: platformFilter)
                } else {
                    self = .product(target: target, productName: productName)
                }
            case .sdk(path: let path, status: _, source: _):
                self = .sdk(path: path)
            }
        }
    }
}
