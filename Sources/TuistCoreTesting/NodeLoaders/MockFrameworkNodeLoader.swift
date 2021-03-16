import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class MockFrameworkLoader: FrameworkLoading {
    public init() {}

    var loadNodeStub: ((AbsolutePath) throws -> FrameworkNode)?

    public func load(path: AbsolutePath) throws -> FrameworkNode {
        if let loadStub = loadNodeStub {
            return try loadStub(path)
        } else {
            return FrameworkNode.test(path: path)
        }
    }
    
    var loadStub: ((AbsolutePath) throws -> ValueGraphDependency)?
    public func load(path: AbsolutePath) throws -> ValueGraphDependency {
        if let loadStub = loadStub {
            return try loadStub(path)
        } else {
            return ValueGraphDependency.testFramework(path: path)
        }
    }
}
