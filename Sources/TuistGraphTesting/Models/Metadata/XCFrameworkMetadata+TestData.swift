import Foundation
import TSCBasic
import TuistSupport
@testable import TuistGraph

extension XCFrameworkMetadata {
    public static func test(
        path: AbsolutePath = "/XCFrameworks/XCFramework.xcframework",
        infoPlist: XCFrameworkInfoPlist = .test(),
        primaryBinaryPath: AbsolutePath = "/XCFrameworks/XCFramework.xcframework/ios-arm64/XCFramework",
        linking: BinaryLinking = .dynamic,
        mergeable: Bool = false,
        status: FrameworkStatus = .required,
        macroPath: AbsolutePath? = nil
    ) -> XCFrameworkMetadata {
        XCFrameworkMetadata(
            path: path,
            infoPlist: infoPlist,
            primaryBinaryPath: primaryBinaryPath,
            linking: linking,
            mergeable: mergeable,
            status: status,
            macroPath: macroPath
        )
    }
}
