import Basic
import Foundation

@testable import TuistCore

public extension FrameworkNode {
    static func test(path: AbsolutePath = "/Test.framework") -> FrameworkNode {
        return FrameworkNode(path: path)
    }
}
