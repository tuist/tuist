import Foundation
import TSCBasic

@testable import TuistCore

public extension XCFrameworkNode {
    static func test(path: AbsolutePath = "/MyFramework/MyFramework.xcframework",
                     infoPlist: XCFrameworkInfoPlist = .test(),
                     primaryBinaryPath: AbsolutePath = "/MyFramework/MyFramework.xcframework/binary",
                     linking: BinaryLinking = .dynamic,
                     dependencies: [XCFrameworkNode.Dependency] = []) -> XCFrameworkNode
    {
        XCFrameworkNode(path: path,
                        infoPlist: infoPlist,
                        primaryBinaryPath: primaryBinaryPath,
                        linking: linking,
                        dependencies: dependencies)
    }
}
