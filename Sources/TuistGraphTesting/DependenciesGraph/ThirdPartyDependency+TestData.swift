import Foundation
import TSCBasic
import TuistGraph

public extension ThirdPartyDependency {
    static func testXCFramework(
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework"))
    ) -> Self {
        return .xcframework(path: path)
    }
}
