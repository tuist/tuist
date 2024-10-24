import Foundation
import Path
import XcodeGraph

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    var condition: PlatformCondition? {
        switch self {
        case let .framework(_, _, _, _, _, _, _, _, condition),
             let .library(_, _, _, _, condition),
             let .xcframework(_, _, _, condition),
             let .bundle(_, condition),
             let .product(_, _, _, condition),
             let .sdk(_, _, _, condition),
             let .packageProduct(_, condition):
            return condition
        case .macro:
            return nil
        }
    }

    case macro(path: AbsolutePath)
    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        status: LinkingStatus,
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
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product,
        status: LinkingStatus,
        condition: PlatformCondition? = nil
    )
    case bundle(path: AbsolutePath, condition: PlatformCondition? = nil)
    case product(
        target: String, productName: String, status: LinkingStatus = .required,
        condition: PlatformCondition? = nil
    )
    case sdk(
        path: AbsolutePath, status: LinkingStatus, source: SDKSource,
        condition: PlatformCondition? = nil
    )
    case packageProduct(product: String, condition: PlatformCondition? = nil)

    init(_ dependency: GraphDependency, condition: PlatformCondition? = nil) {
        switch dependency {
        case let .framework(
            path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, status
        ):
            self = .framework(
                path: path,
                binaryPath: binaryPath,
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
        case let .framework(path, _, _, _, _, _, _, _, _):
            return path
        case let .library(path, _, _, _, _):
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
        case macro(path: AbsolutePath)
        case sdk(path: AbsolutePath, condition: PlatformCondition?)
        case product(target: String, productName: String, condition: PlatformCondition?)
        case library(path: AbsolutePath, condition: PlatformCondition?)
        case framework(path: AbsolutePath, condition: PlatformCondition?)
        case xcframework(path: AbsolutePath, condition: PlatformCondition?)
        case bundle(path: AbsolutePath, condition: PlatformCondition?)
        case packageProduct(product: String, condition: PlatformCondition?)

        init(dependencyReference: GraphDependencyReference) {
            switch dependencyReference {
            case let .macro(path):
                self = .macro(path: path)
            case .xcframework(
                let path,
                infoPlist: _,
                status: _, let condition
            ):
                self = .xcframework(path: path, condition: condition)
            case let .library(path: path, _, _, _, condition):
                self = .library(path: path, condition: condition)
            case .framework(
                let path,
                binaryPath: _,
                dsymPath: _,
                bcsymbolmapPaths: _,
                linking: _,
                architectures: _,
                product: _,
                status: _, let condition
            ):
                self = .framework(path: path, condition: condition)
            case let .bundle(path: path, condition):
                self = .bundle(path: path, condition: condition)
            case let .product(target: target, productName: productName, _, condition: condition):
                self = .product(target: target, productName: productName, condition: condition)
            case .sdk(let path, status: _, source: _, let condition):
                self = .sdk(path: path, condition: condition)
            case let .packageProduct(product, condition):
                self = .packageProduct(product: product, condition: condition)
            }
        }
    }
}

extension PlatformCondition?: Swift.Comparable {
    public static func < (lhs: Optional, rhs: Optional) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return lhs < rhs
    }
}
