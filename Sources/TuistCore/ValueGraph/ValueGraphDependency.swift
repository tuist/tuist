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
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture]
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

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .xcframework(path, _, _, _):
            hasher.combine(path)
        case let .framework(path, _, _, _, _):
            hasher.combine(path)
        case let .library(path, _, _, _, _):
            hasher.combine(path)
        case let .packageProduct(path, product):
            hasher.combine(path)
            hasher.combine(product)
        case let .target(name, path):
            hasher.combine(name)
            hasher.combine(path)
        }
    }
}
