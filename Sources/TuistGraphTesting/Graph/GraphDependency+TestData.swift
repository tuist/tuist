import Foundation
import TSCBasic

@testable import TuistGraph

extension GraphDependency {
    public static func testFramework(
        path: AbsolutePath = AbsolutePath.root.appending(component: "Test.framework"),
        binaryPath: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.framework/Test")),
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.armv7],
        isCarthage: Bool = false
    ) -> GraphDependency {
        GraphDependency.framework(
            path: path,
            binaryPath: binaryPath,
            dsymPath: dsymPath,
            bcsymbolmapPaths: bcsymbolmapPaths,
            linking: linking,
            architectures: architectures,
            isCarthage: isCarthage
        )
    }

    public static func testXCFramework(
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = AbsolutePath.root
            .appending(RelativePath("Test.xcframework/Test")),
        linking: BinaryLinking = .dynamic
    ) -> GraphDependency {
        .xcframework(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking
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
        name: String = "XCTest",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("XCTest.framework")),
        status: SDKStatus = .required,
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
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("libTuist.a")),
        publicHeaders: AbsolutePath = AbsolutePath.root.appending(RelativePath("headers")),
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

    public static func testPackageProduct(
        path: AbsolutePath = .root,
        product: String = "Tuist"
    ) -> GraphDependency {
        .packageProduct(
            path: path,
            product: product
        )
    }
}
