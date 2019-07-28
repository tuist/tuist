import Basic
import Foundation

@testable import TuistGenerator

extension FrameworkNode {
    static func test(path: AbsolutePath = "/Test.framework") -> FrameworkNode {
        return FrameworkNode(path: path)
    }
}
