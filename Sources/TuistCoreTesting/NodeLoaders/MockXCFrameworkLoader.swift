import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class MockXCFrameworkLoader: XCFrameworkLoading {
    public init() {}

    var loadNodeStub: ((AbsolutePath) throws -> XCFrameworkNode)?
    public func load(path: AbsolutePath) throws -> XCFrameworkNode {
        if let loadStub = loadNodeStub {
            return try loadStub(path)
        } else {
            return XCFrameworkNode.test(path: path)
        }
    }
    
    var loadStub: ((AbsolutePath) throws -> ValueGraphDependency)?
    public func load(path: AbsolutePath) throws -> ValueGraphDependency {
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return .testXCFramework(path: path)
        }
    }
}
