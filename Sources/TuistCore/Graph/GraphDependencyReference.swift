import Foundation
import TSCBasic
import TuistGraph

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        binaryPath: AbsolutePath,
        status: FrameworkStatus,
        platformFilters: PlatformFilters
    )
    case library(
        path: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product,
        platformFilters: PlatformFilters
    )
    case framework(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        isCarthage: Bool,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product,
        status: FrameworkStatus,
        platformFilters: PlatformFilters
    )
    case bundle(path: AbsolutePath, platformFilters: PlatformFilters)
    case product(target: String, productName: String, platformFilters: PlatformFilters)
    case sdk(path: AbsolutePath, status: SDKStatus, source: SDKSource, platformFilters: PlatformFilters)

    init(_ dependency: GraphDependency, filters: PlatformFilters = .all) {
        switch dependency {
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, isCarthage, status):
            self = .framework(
                path: path,
                binaryPath: binaryPath,
                isCarthage: isCarthage,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticFramework : .framework,
                status: status,
                platformFilters: filters
            )
        case let .library(path, _, linking, architectures, _):
            self = .library(
                path: path,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticLibrary : .dynamicLibrary,
                platformFilters: filters
            )
        case let .xcframework(path, infoPlist, primaryBinaryPath, _, _, status):
            self = .xcframework(
                path: path,
                infoPlist: infoPlist,
                primaryBinaryPath: primaryBinaryPath,
                binaryPath: primaryBinaryPath,
                status: status,
                platformFilters: filters
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
        case let .framework(path, _, _, _, _, _, _, _, _, _):
            return path
        case let .library(path, _, _, _, _):
            return path
        case let .xcframework(path, _, _, _, _, _):
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
        case sdk(path: AbsolutePath, platformFilters: PlatformFilters)
        case product(target: String, productName: String, platformFilters: PlatformFilters)
        case productWithPlatformFilters(target: String, productName: String, platformFilters: PlatformFilters)
        case library(path: AbsolutePath, platformFilters: PlatformFilters)
        case framework(path: AbsolutePath, platformFilters: PlatformFilters)
        case xcframework(path: AbsolutePath, platformFilters: PlatformFilters)
        case bundle(path: AbsolutePath, platformFilters: PlatformFilters)

        init(dependencyReference: GraphDependencyReference) {
            switch dependencyReference {
            case .xcframework(
                path: let path,
                infoPlist: _,
                primaryBinaryPath: _,
                binaryPath: _,
                status: _,
                platformFilters: let platformFilters
            ):
                self = .xcframework(path: path, platformFilters: platformFilters)
            case let .library(path: path, _, _, _, platformFilters):
                self = .library(path: path, platformFilters: platformFilters)
            case .framework(
                path: let path,
                binaryPath: _,
                isCarthage: _,
                dsymPath: _,
                bcsymbolmapPaths: _,
                linking: _,
                architectures: _,
                product: _,
                status: _,
                platformFilters: let platformFilters
            ):
                self = .framework(path: path, platformFilters: platformFilters)
            case let .bundle(path: path, platformFilters):
                self = .bundle(path: path, platformFilters: platformFilters)
            case let .product(target: target, productName: productName, platformFilters: platformFilters):
                if !platformFilters.isEmpty {
                    self = .productWithPlatformFilters(target: target, productName: productName, platformFilters: platformFilters)
                } else {
                    self = .product(target: target, productName: productName, platformFilters: platformFilters)
                }
            case .sdk(path: let path, status: _, source: _, platformFilters: let platformFilters):
                self = .sdk(path: path, platformFilters: platformFilters)
            }
        }
    }
}
