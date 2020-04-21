import Foundation
import TSCBasic

@testable import TuistCore

public extension CocoaPodsNode {
    static func test(path: AbsolutePath = AbsolutePath("/")) -> CocoaPodsNode {
        CocoaPodsNode(path: path)
    }
}
