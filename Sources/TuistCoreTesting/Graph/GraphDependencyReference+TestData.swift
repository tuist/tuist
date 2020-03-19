import Basic
import Foundation
import TuistCore

public extension GraphDependencyReference {
    static func testFramework(
        path: AbsolutePath = "/path/tuist.framework",
        binaryPath: AbsolutePath = "/path/tuist.framework/tuist",
        isCarthage: Bool = false,
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        product: Product = .framework
    ) -> GraphDependencyReference {
        GraphDependencyReference.framework(path: path,
                                           binaryPath: binaryPath,
                                           isCarthage: isCarthage,
                                           dsymPath: dsymPath,
                                           bcsymbolmapPaths: bcsymbolmapPaths,
                                           linking: linking,
                                           architectures: architectures,
                                           product: product)
    }

    static func testXCFramework(
        path: AbsolutePath = "/path/tuist.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/path/tuist.xcframework/ios-arm64/tuist",
        binaryPath: AbsolutePath
    ) -> GraphDependencyReference {
        GraphDependencyReference.xcframework(path: path,
                                             infoPlist: infoPlist,
                                             primaryBinaryPath: primaryBinaryPath,
                                             binaryPath: binaryPath)
    }

    static func testLibrary(path: AbsolutePath,
                            binaryPath: AbsolutePath,
                            linking: BinaryLinking,
                            architectures: [BinaryArchitecture],
                            product: Product) -> GraphDependencyReference {
        GraphDependencyReference.library(path: path,
                                         binaryPath: binaryPath,
                                         linking: linking,
                                         architectures: architectures,
                                         product: product)
    }

    static func testSDK(path: AbsolutePath, status: SDKStatus) -> GraphDependencyReference {
        GraphDependencyReference.sdk(path: path,
                                     status: status)
    }

    static func testProduct(target: String, productName: String) -> GraphDependencyReference {
        GraphDependencyReference.product(target: target,
                                         productName: productName)
    }
}
