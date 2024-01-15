import Foundation
import TSCBasic
import TuistGraph

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    var condition: PlatformCondition? {
        switch self {
        case let .framework(_, _, _, _, _, _, _, _, _, condition),
             let .library(_, _, _, _, condition),
             let .xcframework(_, _, _, _, _, condition),
             let .bundle(_, condition),
             let .product(_, _, condition),
             let .sdk(_, _, _, condition):
            return condition
        }
    }

    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        binaryPath: AbsolutePath,
        status: FrameworkStatus,
        condition: PlatformCondition? = nil
    )
    case library(
        path: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product,
        condition: PlatformCondition? = nil
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
        condition: PlatformCondition? = nil
    )
    case bundle(path: AbsolutePath, condition: PlatformCondition? = nil)
    case product(target: String, productName: String, condition: PlatformCondition? = nil)
    case sdk(path: AbsolutePath, status: SDKStatus, source: SDKSource, condition: PlatformCondition? = nil)

    init(_ dependency: GraphDependency, condition: PlatformCondition? = nil) {
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
                condition: condition
            )
        case let .library(path, _, linking, architectures, _):
            self = .library(
                path: path,
                linking: linking,
                architectures: architectures,
                product: (linking == .static) ? .staticLibrary : .dynamicLibrary,
                condition: condition
            )
        case let .xcframework(xcframework):
            self = .xcframework(
                path: xcframework.path,
                infoPlist: xcframework.infoPlist,
                primaryBinaryPath: xcframework.primaryBinaryPath,
                binaryPath: xcframework.primaryBinaryPath,
                status: xcframework.status,
                condition: condition
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
        case sdk(path: AbsolutePath, condition: PlatformCondition?)
        case product(target: String, productName: String, condition: PlatformCondition?)
        case library(path: AbsolutePath, condition: PlatformCondition?)
        case framework(path: AbsolutePath, condition: PlatformCondition?)
        case xcframework(path: AbsolutePath, condition: PlatformCondition?)
        case bundle(path: AbsolutePath, condition: PlatformCondition?)

        init(dependencyReference: GraphDependencyReference) {
            switch dependencyReference {
            case .xcframework(
                path: let path,
                infoPlist: _,
                primaryBinaryPath: _,
                binaryPath: _,
                status: _,
                condition: let condition
            ):
                self = .xcframework(path: path, condition: condition)
            case let .library(path: path, _, _, _, condition):
                self = .library(path: path, condition: condition)
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
                condition: let condition
            ):
                self = .framework(path: path, condition: condition)
            case let .bundle(path: path, condition):
                self = .bundle(path: path, condition: condition)
            case let .product(target: target, productName: productName, condition: condition):
                self = .product(target: target, productName: productName, condition: condition)
            case .sdk(path: let path, status: _, source: _, condition: let condition):
                self = .sdk(path: path, condition: condition)
            }
        }
    }
}

extension PlatformCondition?: Comparable {
    public static func < (lhs: Optional, rhs: Optional) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return lhs < rhs
    }
}
