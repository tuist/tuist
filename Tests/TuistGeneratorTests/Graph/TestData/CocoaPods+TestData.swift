import Basic
import Foundation

@testable import TuistGenerator

extension CocoaPodsNode {
    static func test(path: AbsolutePath = "/") -> CocoaPodsNode {
        return CocoaPodsNode(path: path)
    }
}
