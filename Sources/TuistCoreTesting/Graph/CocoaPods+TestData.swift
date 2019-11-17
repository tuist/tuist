import Basic
import Foundation

@testable import TuistCore

public extension CocoaPodsNode {
    static func test(path: AbsolutePath = AbsolutePath("/")) -> CocoaPodsNode {
        return CocoaPodsNode(path: path)
    }
}
