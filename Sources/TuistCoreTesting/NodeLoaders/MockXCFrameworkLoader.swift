import Foundation
import TSCBasic
import TuistCore

public final class MockXCFrameworkNodeLoader: XCFrameworkNodeLoading {
    public init() {}

    var loadStub: ((AbsolutePath) throws -> XCFrameworkNode)?
    public func load(path: AbsolutePath) throws -> XCFrameworkNode {
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return XCFrameworkNode.test(path: path)
        }
    }
}
