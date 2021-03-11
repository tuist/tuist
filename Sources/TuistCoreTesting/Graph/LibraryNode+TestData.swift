import Foundation
import TSCBasic
import TuistGraph
@testable import TuistCore

public extension LibraryNode {
    static func test(path: AbsolutePath = "/Library/libTest.a",
                     publicHeaders: AbsolutePath = "/Library/TestHeaders/",
                     architectures: [BinaryArchitecture] = [.arm64],
                     linking: BinaryLinking = .static,
                     swiftModuleMap: AbsolutePath? = nil) -> LibraryNode
    {
        LibraryNode(
            path: path,
            publicHeaders: publicHeaders,
            architectures: architectures,
            linking: linking,
            swiftModuleMap: swiftModuleMap
        )
    }
}
