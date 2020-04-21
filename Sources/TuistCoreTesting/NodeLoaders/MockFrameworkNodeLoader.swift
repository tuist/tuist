import Foundation
import TSCBasic
import TuistCore

public final class MockFrameworkNodeLoader: FrameworkNodeLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> FrameworkNode)?

    public func load(path: AbsolutePath) throws -> FrameworkNode {
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return FrameworkNode.test(path: path)
        }
    }
}
