import Foundation
import TSCBasic

@testable import TuistCore

public extension FrameworkNode {
    static func test(path: AbsolutePath = "/path/to/Framework.framework",
                     dsymPath: AbsolutePath? = nil,
                     bcsymbolmapPaths: [AbsolutePath] = [],
                     linking: BinaryLinking = .dynamic,
                     architectures: [BinaryArchitecture] = [],
                     dependencies: [FrameworkNode] = []) -> FrameworkNode
    {
        FrameworkNode(path: path,
                      dsymPath: dsymPath,
                      bcsymbolmapPaths: bcsymbolmapPaths,
                      linking: linking,
                      architectures: architectures,
                      dependencies: dependencies)
    }
}
