import Foundation
import Path

public enum GraphDependency: Hashable, CustomStringConvertible, Comparable, Codable, Sendable {
    public struct XCFramework: Hashable, CustomStringConvertible, Comparable, Codable, Sendable {
        public var path: AbsolutePath
        public var infoPlist: XCFrameworkInfoPlist
        public var linking: BinaryLinking
        public var mergeable: Bool
        public var status: LinkingStatus
        public var swiftModules: [AbsolutePath]
        public var moduleMaps: [AbsolutePath]
        public var expectedSignature: String?

        public init(
            path: AbsolutePath,
            infoPlist: XCFrameworkInfoPlist,
            linking: BinaryLinking,
            mergeable: Bool,
            status: LinkingStatus,
            swiftModules: [AbsolutePath],
            moduleMaps: [AbsolutePath],
            expectedSignature: String? = nil
        ) {
            self.path = path
            self.infoPlist = infoPlist
            self.linking = linking
            self.mergeable = mergeable
            self.status = status
            self.swiftModules = swiftModules
            self.moduleMaps = moduleMaps
            self.expectedSignature = expectedSignature
        }

        public var description: String {
            "xcframework '\(path.basename)'"
        }

        public static func < (lhs: GraphDependency.XCFramework, rhs: GraphDependency.XCFramework) -> Bool {
            lhs.description < rhs.description
        }
    }

    public enum PackageProductType: String, Hashable, CustomStringConvertible, Comparable, Codable, Sendable {
        public var description: String {
            rawValue
        }

        case runtime = "runtime package product"
        case runtimeEmbedded = "runtime embedded package product"
        case plugin = "plugin package product"
        case macro = "macro package product"

        public static func < (lhs: PackageProductType, rhs: PackageProductType) -> Bool {
            lhs.description < rhs.description
        }
    }

    public struct ForeignBuildOutput: Hashable, CustomStringConvertible, Comparable, Codable, Sendable {
        public var name: String
        public var path: AbsolutePath
        public var linking: BinaryLinking

        public init(name: String, path: AbsolutePath, linking: BinaryLinking) {
            self.name = name
            self.path = path
            self.linking = linking
        }

        public var description: String {
            "foreign build output '\(name)'"
        }

        public static func < (lhs: ForeignBuildOutput, rhs: ForeignBuildOutput) -> Bool {
            lhs.description < rhs.description
        }
    }

    case foreignBuildOutput(ForeignBuildOutput)

    case xcframework(GraphDependency.XCFramework)

    /// A dependency that represents a pre-compiled framework.
    case framework(
        path: AbsolutePath,
        binaryPath: AbsolutePath,
        dsymPath: AbsolutePath?,
        bcsymbolmapPaths: [AbsolutePath],
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        status: LinkingStatus
    )

    /// A dependency that represents a pre-compiled library.
    case library(
        path: AbsolutePath,
        publicHeaders: AbsolutePath,
        linking: BinaryLinking,
        architectures: [BinaryArchitecture],
        swiftModuleMap: AbsolutePath?
    )

    /// A macOS executable that represents a macro
    case macro(path: AbsolutePath)

    /// A dependency that represents a pre-compiled bundle.
    case bundle(path: AbsolutePath)

    /// A dependency that represents a package product.
    case packageProduct(path: AbsolutePath, product: String, type: PackageProductType)

    /// A dependency that represents a target that is defined in the project at the given path.
    case target(name: String, path: AbsolutePath, status: LinkingStatus = .required)

    /// A dependency that represents an SDK
    case sdk(name: String, path: AbsolutePath, status: LinkingStatus, source: SDKSource)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .macro(path):
            hasher.combine(path)
        case let .foreignBuildOutput(output):
            hasher.combine("foreignBuildOutput")
            hasher.combine(output)
        case let .xcframework(xcframework):
            hasher.combine(xcframework)
        case let .framework(path, _, _, _, _, _, _):
            hasher.combine("framework")
            hasher.combine(path)
        case let .library(path, _, _, _, _):
            hasher.combine("library")
            hasher.combine(path)
        case let .bundle(path):
            hasher.combine("bundle")
            hasher.combine(path)
        case let .packageProduct(path, product, isPlugin):
            hasher.combine("package")
            hasher.combine(path)
            hasher.combine(product)
            hasher.combine(isPlugin)
        case let .target(name, path, _):
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
        case .macro: return false
        case .foreignBuildOutput: return false
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .bundle: return false
        case .packageProduct: return false
        case .target: return true
        case .sdk: return false
        }
    }

    /**
     When the graph dependency represents a pre-compiled static binary.
     */
    public var isStaticPrecompiled: Bool {
        switch self {
        case .macro: return false
        case let .foreignBuildOutput(output): return output.linking == .static
        case let .xcframework(xcframework):
            return xcframework.linking == .static
        case let .framework(_, _, _, _, linking, _, _),
             let .library(_, _, linking, _, _): return linking == .static
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    /**
     When the graph dependency represents a dynamic precompiled binary, it returns true.
     */
    public var isDynamicPrecompiled: Bool {
        switch self {
        case .macro: return false
        case let .foreignBuildOutput(output): return output.linking == .dynamic
        case let .xcframework(xcframework):
            return xcframework.linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _),
             let .library(_, _, linking, _, _): return linking == .dynamic
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    public var isPrecompiled: Bool {
        switch self {
        case .macro: return true
        case .foreignBuildOutput: return true
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .bundle: return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    public var isLinkable: Bool {
        switch self {
        case .macro: return false
        case .foreignBuildOutput: return true
        case .xcframework: return true
        case .framework: return true
        case .library: return true
        case .bundle: return false
        case .packageProduct: return true
        case .target: return true
        case .sdk: return true
        }
    }

    public var isPrecompiledMacro: Bool {
        switch self {
        case .macro: return true
        case .foreignBuildOutput: return false
        case .xcframework: return false
        case .framework: return false
        case .library: return false
        case .bundle: return false
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    public var isPrecompiledDynamicAndLinkable: Bool {
        switch self {
        case .macro: return false
        case let .foreignBuildOutput(output): return output.linking == .dynamic
        case let .xcframework(xcframework):
            return xcframework.linking == .dynamic
        case let .framework(_, _, _, _, linking, _, _),
             let .library(path: _, publicHeaders: _, linking: linking, architectures: _, swiftModuleMap: _):
            return linking == .dynamic
        case .bundle: return false
        case .packageProduct(_, _, type: .runtimeEmbedded): return true
        case .packageProduct: return false
        case .target: return false
        case .sdk: return false
        }
    }

    // MARK: - Internal

    public var targetDependency: (name: String, path: AbsolutePath)? {
        switch self {
        case let .target(name: name, path: path, _):
            return (name, path)
        default:
            return nil
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .macro:
            return "macro '\(name)'"
        case let .foreignBuildOutput(output):
            return output.description
        case .xcframework:
            return "xcframework '\(name)'"
        case .framework:
            return "framework '\(name)'"
        case .library:
            return "library '\(name)'"
        case .bundle:
            return "bundle '\(name)'"
        case .packageProduct:
            return "package '\(name)'"
        case .target:
            return "target '\(name)'"
        case .sdk:
            return "sdk '\(name)'"
        }
    }

    public var name: String {
        switch self {
        case let .macro(path):
            return path.basename
        case let .foreignBuildOutput(output):
            return output.name
        case let .xcframework(xcframework):
            return xcframework.path.basename
        case let .framework(path, _, _, _, _, _, _):
            return path.basename
        case let .library(path, _, _, _, _):
            return path.basename
        case let .bundle(path):
            return path.basename
        case let .packageProduct(_, product, _):
            return product
        case let .target(name, _, _):
            return name
        case let .sdk(name, _, _, _):
            return name
        }
    }

    // MARK: - Comparable

    public static func < (lhs: GraphDependency, rhs: GraphDependency) -> Bool {
        lhs.description < rhs.description
    }
}

#if DEBUG
    // swiftlint:disable force_try

    extension GraphDependency {
        public static func testFramework(
            path: AbsolutePath = AbsolutePath.root.appending(component: "Test.framework"),
            binaryPath: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "Test.framework/Test")),
            dsymPath: AbsolutePath? = nil,
            bcsymbolmapPaths: [AbsolutePath] = [],
            linking: BinaryLinking = .dynamic,
            architectures: [BinaryArchitecture] = [.armv7],
            status: LinkingStatus = .required
        ) -> GraphDependency {
            GraphDependency.framework(
                path: path,
                binaryPath: binaryPath,
                dsymPath: dsymPath,
                bcsymbolmapPaths: bcsymbolmapPaths,
                linking: linking,
                architectures: architectures,
                status: status
            )
        }

        public static func testMacro(
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "macro"))
        ) -> GraphDependency {
            .macro(path: path)
        }

        public static func testXCFramework(
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "Test.xcframework")),
            infoPlist: XCFrameworkInfoPlist = .test(),
            linking: BinaryLinking = .dynamic,
            mergeable: Bool = false,
            status: LinkingStatus = .required,
            swiftModules: [AbsolutePath] = [],
            moduleMaps: [AbsolutePath] = []
        ) -> GraphDependency {
            .xcframework(
                GraphDependency.XCFramework(
                    path: path,
                    infoPlist: infoPlist,
                    linking: linking,
                    mergeable: mergeable,
                    status: status,
                    swiftModules: swiftModules,
                    moduleMaps: moduleMaps
                )
            )
        }

        public static func testTarget(
            name: String = "Test",
            path: AbsolutePath = .root
        ) -> GraphDependency {
            .target(
                name: name,
                path: path
            )
        }

        public static func testSDK(
            name: String = "XCTest.framework",
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "XCTest.framework")),
            status: LinkingStatus = .required,
            source: SDKSource = .system
        ) -> GraphDependency {
            .sdk(
                name: name,
                path: path,
                status: status,
                source: source
            )
        }

        public static func testLibrary(
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "libTuist.a")),
            publicHeaders: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "headers")),
            linking: BinaryLinking = .dynamic,
            architectures: [BinaryArchitecture] = [.armv7],
            swiftModuleMap: AbsolutePath? = nil
        ) -> GraphDependency {
            .library(
                path: path,
                publicHeaders: publicHeaders,
                linking: linking,
                architectures: architectures,
                swiftModuleMap: swiftModuleMap
            )
        }

        public static func testForeignBuildOutput(
            name: String = "SharedKMP",
            path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "SharedKMP.xcframework")),
            linking: BinaryLinking = .dynamic
        ) -> GraphDependency {
            .foreignBuildOutput(GraphDependency.ForeignBuildOutput(
                name: name,
                path: path,
                linking: linking
            ))
        }

        public static func testBundle(path: AbsolutePath = .root.appending(component: "test.bundle")) -> GraphDependency {
            .bundle(path: path)
        }

        public static func testPackageProduct(
            path: AbsolutePath = .root,
            product: String = "Tuist"
        ) -> GraphDependency {
            .packageProduct(
                path: path,
                product: product,
                type: .runtime
            )
        }
    }

    // swiftlint:enable force_try
#endif
