import Foundation
import TSCBasic

@testable import TuistGraph

public extension ValueGraphDependency {
    static func testCocoapods(path: AbsolutePath = .root) -> ValueGraphDependency {
        ValueGraphDependency.cocoapods(path: path)
    }

    static func testFramework(path: AbsolutePath = AbsolutePath.root.appending(component: "Test.framework"),
                              binaryPath: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.framework/Test")),
                              dsymPath: AbsolutePath? = nil,
                              bcsymbolmapPaths: [AbsolutePath] = [],
                              linking: BinaryLinking = .dynamic,
                              architectures: [BinaryArchitecture] = [.armv7],
                              isCarthage: Bool = false) -> ValueGraphDependency
    {
        ValueGraphDependency.framework(path: path,
                                       binaryPath: binaryPath,
                                       dsymPath: dsymPath,
                                       bcsymbolmapPaths: bcsymbolmapPaths,
                                       linking: linking,
                                       architectures: architectures,
                                       isCarthage: isCarthage)
    }

    static func testXCFramework(path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
                                infoPlist: XCFrameworkInfoPlist = .test(),
                                primaryBinaryPath: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework/Test")),
                                linking: BinaryLinking = .dynamic) -> ValueGraphDependency
    {
        .xcframework(path: path,
                     infoPlist: infoPlist,
                     primaryBinaryPath: primaryBinaryPath,
                     linking: linking)
    }

    static func testTarget(name: String = "Test",
                           path: AbsolutePath = .root) -> ValueGraphDependency
    {
        .target(name: name,
                path: path)
    }

    static func testSDK(name: String = "XCTest",
                        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("XCTest.framework")),
                        status: SDKStatus = .required,
                        source: SDKSource = .system) -> ValueGraphDependency
    {
        .sdk(name: name,
             path: path,
             status: status,
             source: source)
    }

    static func testLibrary(path: AbsolutePath = AbsolutePath.root.appending(RelativePath("libTuist.a")),
                            publicHeaders: AbsolutePath = AbsolutePath.root.appending(RelativePath("headers")),
                            linking: BinaryLinking = .dynamic,
                            architectures: [BinaryArchitecture] = [.armv7],
                            swiftModuleMap: AbsolutePath? = nil) -> ValueGraphDependency
    {
        .library(path: path,
                 publicHeaders: publicHeaders,
                 linking: linking,
                 architectures: architectures,
                 swiftModuleMap: swiftModuleMap)
    }

    static func testPackageProduct(path: AbsolutePath = .root,
                                   product: String = "Tuist") -> ValueGraphDependency
    {
        .packageProduct(path: path,
                        product: product)
    }
}
