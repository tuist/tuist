import Foundation
import TSCBasic

@testable import TuistGraph

extension XCFrameworkMetadata {
    public static func test(
        path: AbsolutePath = "/XCFrameworks/XCFramework.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/XCFrameworks/XCFramework.xcframework/ios-arm64/XCFramework",
        linking: BinaryLinking = .dynamic,
        mergeable: Bool = false
    ) -> XCFrameworkMetadata {
        XCFrameworkMetadata(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking,
            mergeable: mergeable
        )
    }
}
