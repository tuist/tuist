import Foundation
import TSCBasic

@testable import TuistGraph

// swiftlint:disable force_try

extension GraphDependency {
    public static func testFramework(
        path: AbsolutePath = AbsolutePath.root.appending(component: "Test.framework"),
        binaryPath: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "Test.framework/Test")),
        dsymPath: AbsolutePath? = nil,
        bcsymbolmapPaths: [AbsolutePath] = [],
        linking: BinaryLinking = .dynamic,
        architectures: [BinaryArchitecture] = [.armv7],
        status: FrameworkStatus = .required
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
        primaryBinaryPath: AbsolutePath = AbsolutePath.root
            .appending(try! RelativePath(validating: "Test.xcframework/Test")),
        linking: BinaryLinking = .dynamic,
        status: FrameworkStatus = .required,
        macroPath: AbsolutePath? = nil
    ) -> GraphDependency {
        .xcframework(
            GraphDependency.XCFramework(
                path: path,
                infoPlist: infoPlist,
                primaryBinaryPath: primaryBinaryPath,
                linking: linking,
                mergeable: false,
                status: status,
                macroPath: macroPath
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
        name: String = "XCTest",
        path: AbsolutePath = AbsolutePath.root.appending(try! RelativePath(validating: "XCTest.framework")),
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
