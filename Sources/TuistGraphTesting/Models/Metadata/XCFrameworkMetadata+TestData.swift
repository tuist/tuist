import Foundation
import TSCBasic

@testable import TuistGraph

extension XCFrameworkMetadata {
    public static func test(
        path: AbsolutePath = "/XCFrameworks/XCFramework.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/XCFrameworks/XCFramework.xcframework/ios-arm64/XCFramework",
        linking: BinaryLinking = .dynamic
    ) -> XCFrameworkMetadata {
        XCFrameworkMetadata(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking
        )
    }
}
