import Foundation
import TSCBasic
import TuistGraph

public extension DependenciesGraphNode {
    static func testXCFramework(
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
        architectures: Set<BinaryArchitecture> = []
    ) -> Self {
        return .xcframework(path: path, architectures: architectures)
    }
}
