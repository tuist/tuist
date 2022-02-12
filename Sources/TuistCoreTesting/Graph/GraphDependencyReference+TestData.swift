import Foundation
import TSCBasic
import TuistCore
import TuistGraph

extension GraphDependencyReference {
    public static func testFramework(
        path: AbsolutePath = "/frameworks/tuist.framework",
        binaryPath: AbsolutePath = "/frameworks/tuist.framework/tuist",
        isCarthage: Bool = false,
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        product: Product = .framework
    ) -> GraphDependencyReference {
        GraphDependencyReference.framework(
            path: path,
            binaryPath: binaryPath,
            isCarthage: isCarthage,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            product: product
        )
    }

    public static func testXCFramework(
        path: AbsolutePath = "/frameworks/tuist.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/frameworks/tuist.xcframework/ios-arm64/tuist",
        binaryPath: AbsolutePath = "/frameworks/tuist.xcframework/ios-arm64/tuist",
        linking _: BinaryLinking = .dynamic
    ) -> GraphDependencyReference {
        GraphDependencyReference.xcframework(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            binaryPath: binaryPath
        )
    }

    public static func testLibrary(
        path: AbsolutePath = "/libraries/library.a",
        linking: BinaryLinking = .static,
        architectures: [BinaryArchitecture] = [BinaryArchitecture.arm64],
        product: Product = .staticLibrary
    ) -> GraphDependencyReference {
        GraphDependencyReference.library(
            path: path,
            linking: linking,
            architectures: architectures,
            product: product
        )
    }

    public static func testSDK(
        path: AbsolutePath = "/path/CoreData.framework",
        status: SDKStatus = .required,
        source: SDKSource = .system
    ) -> GraphDependencyReference {
        GraphDependencyReference.sdk(
            path: path,
            status: status,
            source: source
        )
    }

    public static func testProduct(
        target: String = "Target",
        productName: String = "Target.framework",
        platformFilter: BuildFilePlatformFilter = .ios
    ) -> GraphDependencyReference {
        GraphDependencyReference.product(
            target: target,
            productName: productName,
            platformFilter: platformFilter
        )
    }
}
