import Foundation
import TSCBasic

public enum ValueGraphDependency: Hashable, CustomStringConvertible, Comparable, Codable {
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
        case let .packageProduct(_, product):
            return "package '\(product)'"
        case let .target(name, _):
            return "target '\(name)'"
        case let .sdk(name, _, _, _):
            return "sdk '\(name)'"
        case let .cocoapods(path):
            return "cocoapods '\(path)'"
        }
    }

    // MARK: - Comparable

    public static func < (lhs: ValueGraphDependency, rhs: ValueGraphDependency) -> Bool {
        lhs.description < rhs.description
    }
    
    // MARK: - Codable
    
    private enum Kind: String, Codable {
        case xcframework
        case framework
        case library
        case packageProduct
        case target
        case sdk
        case cocoapods
    }
    
    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case infoPlist
        case primaryBinaryPath
        case linking
        case binaryPath
        case dsymPath
        case bcsymbolmapPaths
        case architectures
        case isCarthage
        case publicHeaders
        case swiftModuleMap
        case product
        case name
        case status
        case source
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .xcframework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let infoPlist = try container.decode(XCFrameworkInfoPlist.self, forKey: .infoPlist)
            let primaryBinaryPath = try container.decode(AbsolutePath.self, forKey: .primaryBinaryPath)
            let linking = try container.decode(BinaryLinking.self, forKey: .linking)
            self = .xcframework(
                path: path,
                infoPlist: infoPlist,
                primaryBinaryPath: primaryBinaryPath,
                linking: linking
            )
        case .framework:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let binaryPath = try container.decode(AbsolutePath.self, forKey: .binaryPath)
            let dsymPath = try container.decode(AbsolutePath?.self, forKey: .dsymPath)
            let bcsymbolmapPaths = try container.decode([AbsolutePath].self, forKey: .bcsymbolmapPaths)
            let linking = try container.decode(BinaryLinking.self, forKey: .linking)
            let architectures = try container.decode([BinaryArchitecture].self, forKey: .architectures)
            let isCarthage = try container.decode(Bool.self, forKey: .isCarthage)
            self = .framework(
                path: path,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                isCarthage: isCarthage
            )
        case .library:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let publicHeaders = try container.decode(AbsolutePath.self, forKey: .publicHeaders)
            let linking = try container.decode(BinaryLinking.self, forKey: .linking)
            let architectures = try container.decode([BinaryArchitecture].self, forKey: .architectures)
            let swiftModuleMap = try container.decode(AbsolutePath?.self, forKey: .swiftModuleMap)
            self = .library(
                path: path,
                publicHeaders: publicHeaders,
                linking: linking,
                architectures: architectures,
                swiftModuleMap: swiftModuleMap
            )
        case .packageProduct:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let product = try container.decode(String.self, forKey: .product)
            self = .packageProduct(path: path, product: product)
        case .target:
            let name = try container.decode(String.self, forKey: .path)
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .target(name: name, path: path)
        case .sdk:
            let name = try container.decode(String.self, forKey: .path)
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            let status = try container.decode(SDKStatus.self, forKey: .status)
            let source = try container.decode(SDKSource.self, forKey: .source)
            self = .sdk(
                name: name,
                path: path,
                status: status,
                source: source
            )
        case .cocoapods:
            let path = try container.decode(AbsolutePath.self, forKey: .path)
            self = .cocoapods(path: path)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .xcframework(path, infoPlist, primaryBinaryPath, linking):
            try container.encode(Kind.xcframework, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(infoPlist, forKey: .infoPlist)
            try container.encode(primaryBinaryPath, forKey: .primaryBinaryPath)
            try container.encode(linking, forKey: .linking)
        case let .framework(path, binaryPath, dsymPath, bcsymbolmapPaths, linking, architectures, isCarthage):
            try container.encode(Kind.framework, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(binaryPath, forKey: .binaryPath)
            try container.encode(dsymPath, forKey: .dsymPath)
            try container.encode(bcsymbolmapPaths, forKey: .bcsymbolmapPaths)
            try container.encode(linking, forKey: .linking)
            try container.encode(architectures, forKey: .architectures)
            try container.encode(isCarthage, forKey: .isCarthage)
        case let .library(path, publicHeaders, linking, architectures, swiftModuleMap):
            try container.encode(Kind.library, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(publicHeaders, forKey: .publicHeaders)
            try container.encode(linking, forKey: .linking)
            try container.encode(architectures, forKey: .architectures)
            try container.encode(swiftModuleMap, forKey: .swiftModuleMap)
        case let .packageProduct(path, product):
            try container.encode(Kind.packageProduct, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(product, forKey: .product)
        case let .target(name, path):
            try container.encode(Kind.target, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
        case let .sdk(name, path, status, source):
            try container.encode(Kind.sdk, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(path, forKey: .path)
            try container.encode(status, forKey: .status)
            try container.encode(source, forKey: .source)
        case let .cocoapods(path):
            try container.encode(Kind.cocoapods, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
