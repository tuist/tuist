import Basic
import Foundation

@testable import TuistGenerator

extension LibraryNode {
    static func test(path: AbsolutePath = "/libTest.a",
                     publicHeaders: AbsolutePath = "/TestHeaders/") -> LibraryNode {
        return LibraryNode(path: path, publicHeaders: publicHeaders)
    }
}
