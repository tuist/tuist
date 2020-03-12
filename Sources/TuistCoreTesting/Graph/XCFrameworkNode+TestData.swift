import Basic
import Foundation

@testable import TuistCore

public extension XCFrameworkNode {
    static func test(path: AbsolutePath = "/MyFramework/MyFramework.xcframework",
                     infoPlist: XCFrameworkInfoPlist = .test(),
                     primaryBinaryPath: AbsolutePath = "/MyFramework/MyFramework.xcframework/binary",
                     dependencies: [XCFrameworkNode] = []) -> XCFrameworkNode {
        XCFrameworkNode(path: path,
                        infoPlist: infoPlist,
                        primaryBinaryPath: primaryBinaryPath,
                        dependencies: dependencies)
    }
}
