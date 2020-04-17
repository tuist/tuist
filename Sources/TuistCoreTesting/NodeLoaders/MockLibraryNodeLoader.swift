import Foundation
import TSCBasic
import TuistCore

public final class MockLibraryNodeLoader: LibraryNodeLoading {
    public init() {}

    var loadStub: ((AbsolutePath, AbsolutePath, AbsolutePath?) throws -> LibraryNode)?
    public func load(path: AbsolutePath, publicHeaders: AbsolutePath, swiftModuleMap: AbsolutePath?) throws -> LibraryNode {
        if let loadStub = loadStub {
            return try loadStub(path, publicHeaders, swiftModuleMap)
        } else {
            return LibraryNode.test(path: path, publicHeaders: publicHeaders, swiftModuleMap: swiftModuleMap)
        }
    }
}
