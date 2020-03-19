import Basic
import Foundation

public enum GraphDependencyReference: Equatable, Comparable, Hashable {
    case xcframework(
        path: AbsolutePath,
        infoPlist: XCFrameworkInfoPlist,
        primaryBinaryPath: AbsolutePath,
        binaryPath: AbsolutePath
    )
    case library(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        product: Product
    )
    case framework(path: AbsolutePath, binaryPath: AbsolutePath, isCarthage: Bool, dsymPath: AbsolutePath?, bcsymbolmapPaths: [AbsolutePath], linking: BinaryLinking, architectures: [BinaryArchitecture], product: Product)
    case product(target: String, productName: String)
    case sdk(path: AbsolutePath, status: SDKStatus)

    init(precompiledNode: PrecompiledNode) {
        if let frameworkNode = precompiledNode as? FrameworkNode {
            self = .framework(path: frameworkNode.path,
                              binaryPath: frameworkNode.binaryPath,
                              isCarthage: frameworkNode.isCarthage,
                              dsymPath: frameworkNode.dsymPath,
                              bcsymbolmapPaths: frameworkNode.bcsymbolmapPaths,
                              linking: frameworkNode.linking,
                              architectures: frameworkNode.architectures,
                              product: frameworkNode.product)
        } else if let libraryNode = precompiledNode as? LibraryNode {
            self = .library(path: libraryNode.path,
                            binaryPath: libraryNode.binaryPath,
                            linking: libraryNode.linking,
                            architectures: libraryNode.architectures,
                            product: libraryNode.product)
        } else if let xcframeworkNode = precompiledNode as? XCFrameworkNode {
            self = .xcframework(path: xcframeworkNode.path,
                                infoPlist: xcframeworkNode.infoPlist,
                                primaryBinaryPath: xcframeworkNode.primaryBinaryPath,
                                binaryPath: xcframeworkNode.binaryPath)
        } else {
            preconditionFailure("unsupported precompiled node")
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .library(metadata):
            hasher.combine(metadata.0)
        case let .framework(metadata):
            hasher.combine(metadata.0)
        case let .xcframework(metadata):
            hasher.combine(metadata.0)
        case let .product(target, productName):
            hasher.combine(target)
            hasher.combine(productName)
        case let .sdk(path, status):
            hasher.combine(path)
            hasher.combine(status)
        }
    }

    /// For dependencies that exists in the file system. This attribute returns the path to them.
    public var path: AbsolutePath? {
        switch self {
        case let .framework(metadata):
            return metadata.path
        case let .library(metadata):
            return metadata.path
        case let .xcframework(metadata):
            return metadata.path
        case let .sdk(metadata):
            return metadata.path
        default:
            return nil
        }
    }

    public static func < (lhs: GraphDependencyReference, rhs: GraphDependencyReference) -> Bool {
        switch (lhs, rhs) {
        case let (.framework(lhsMetadata), .framework(rhsMetadata)):
            return lhsMetadata.path < rhsMetadata.path
        case let (.xcframework(lhsMetadata), .xcframework(rhsMetadata)):
            return lhsMetadata.path < rhsMetadata.path
        case let (.library(lhsMetadata), .library(rhsMetadata)):
            return lhsMetadata.path < rhsMetadata.path
        case let (.product(lhsTarget, lhsProductName), .product(rhsTarget, rhsProductName)):
            if lhsTarget == rhsTarget {
                return lhsProductName < rhsProductName
            }
            return lhsTarget < rhsTarget
        case let (.sdk(lhsPath, _), .sdk(rhsPath, _)):
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
        case (.framework, .xcframework):
            return true
        default:
            return false
        }
    }
}
