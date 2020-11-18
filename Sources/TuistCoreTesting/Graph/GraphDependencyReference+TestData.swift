import Foundation
import TSCBasic
import TuistCore

public extension GraphDependencyReference {
    static func testFramework(
        path: AbsolutePath = "/frameworks/tuist.framework",
        binaryPath: AbsolutePath = "/frameworks/tuist.framework/tuist",
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
        path: AbsolutePath = "/frameworks/tuist.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/frameworks/tuist.xcframework/ios-arm64/tuist",
        binaryPath: AbsolutePath = "/frameworks/tuist.xcframework/ios-arm64/tuist"
    ) -> GraphDependencyReference {
        GraphDependencyReference.xcframework(path: path,
                                             infoPlist: infoPlist,
                                             primaryBinaryPath: primaryBinaryPath,
                                             binaryPath: binaryPath)
    }

    static func testLibrary(path: AbsolutePath = "/libraries/library.a",
                            binaryPath: AbsolutePath = "/libraries/library.a",
                            linking: BinaryLinking = .static,
                            architectures: [BinaryArchitecture] = [BinaryArchitecture.arm64],
                            product: Product = .staticLibrary) -> GraphDependencyReference
    {
        GraphDependencyReference.library(path: path,
                                         binaryPath: binaryPath,
                                         linking: linking,
                                         architectures: architectures,
                                         product: product)
    }

    static func testSDK(path: AbsolutePath = "/path/CoreData.framework",
                        status: SDKStatus = .required,
                        source: SDKSource = .developer) -> GraphDependencyReference
    {
        GraphDependencyReference.sdk(path: path,
                                     status: status,
                                     source: source)
    }

    static func testProduct(target: String = "Target", productName: String = "Target.framework") -> GraphDependencyReference {
        GraphDependencyReference.product(target: target,
                                         productName: productName)
    }
}
