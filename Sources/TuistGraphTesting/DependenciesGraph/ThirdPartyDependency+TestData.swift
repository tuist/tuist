import Foundation
import TSCBasic
import TuistGraph

public extension ThirdPartyDependency {
    static func testXCFramework(
        name: String = "Test",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
        architectures: Set<BinaryArchitecture> = []
    ) -> Self {
        return .xcframework(name: name, path: path, architectures: architectures)
    }
}
