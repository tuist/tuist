import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

extension GraphDependencyReference {
    public static func testFramework(
        path: AbsolutePath = "/frameworks/tuist.framework",
        binaryPath: AbsolutePath = "/frameworks/tuist.framework/tuist",
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.arm64],
        product: Product = .framework,
        status: LinkingStatus = .required,
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.framework(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            product: product,
            status: status,
            condition: condition
        )
    }

    public static func testMacro(
        path: AbsolutePath = "/macros/tuist"
    ) -> GraphDependencyReference {
        GraphDependencyReference.macro(path: path)
    }

    public static func testXCFramework(
        path: AbsolutePath = "/frameworks/tuist.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        linking _: BinaryLinking = .dynamic,
        status: LinkingStatus = .required,
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.xcframework(
            path: path,
            expectedSignature: nil,
            infoPlist: infoPlist,
            status: status,
            condition: condition
        )
    }

    public static func testLibrary(
        path: AbsolutePath = "/libraries/library.a",
        linking: BinaryLinking = .static,
        architectures: [BinaryArchitecture] = [BinaryArchitecture.arm64],
        product: Product = .staticLibrary,
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.library(
            path: path,
            linking: linking,
            architectures: architectures,
            product: product,
            condition: condition
        )
    }

    public static func testSDK(
        path: AbsolutePath = "/path/CoreData.framework",
        status: LinkingStatus = .required,
        source: SDKSource = .system,
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.sdk(
            path: path,
            status: status,
            source: source,
            condition: condition
        )
    }

    public static func testProduct(
        target: String = "Target",
        productName: String = "Target.framework",
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.product(
            target: target,
            productName: productName,
            condition: condition
        )
    }

    public static func testPackageProduct(
        product: String = "Product",
        condition: PlatformCondition? = nil
    ) -> GraphDependencyReference {
        GraphDependencyReference.packageProduct(
            product: product,
            condition: condition
        )
    }
}
